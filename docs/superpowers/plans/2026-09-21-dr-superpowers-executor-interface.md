# Executor Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate "external executor" from "Codex" inside dr-superpowers, so a second executor becomes a registry entry, a wrapper and a ladder block rather than a rewrite of eight files.

**Architecture:** A data file per executor under `reference/executors/`, read only by a new `scripts/executors` helper. The shared machinery — session state, `plan-lint` validation, `review-route` ruling kinds, the roster, the delegated-set helper and the skill prose — becomes keyed by executor id and reads that helper. Each executor keeps its own gate and locator script, because auth models genuinely differ. Codex becomes the first registry entry with no change to its observable behaviour except the inline offload (Task 8) and the reference corrections (Tasks 12-13).

**Tech Stack:** Bash 4 (Git Bash on Windows), `jq`, GNU `timeout`, `cygpath` where present. No new runtime dependency.

**Spec:** docs/superpowers/specs/2026-09-20-dr-superpowers-executor-interface-design.md

**Execution:** inline — `claude --model opus --effort high` — 2 of 18 tasks are heavy (Tasks 4 and 7), so the plan is inline; the 8 four-band tasks exceed a third of 18 and therefore stay in session, which sets the model to opus, and the effort is raised to high because the plan delegates.

## Global Constraints

- Codex's observable behaviour is unchanged except where this plan's Tasks 8, 12 and 13 state otherwise. Any other change to an existing test assertion is a defect, not a test update.
- Every existing name is preserved: the ladder block literally called `gate`, the environment variable `DR_CODEX_SESSION_DIR`, the session directory `codex-sessions`, and the remedy text embedded in the reason strings.
- The plan file syntax does not change. `**Executor:** codex gpt-5.5 / high` and `> **External executors:** codex` already lead with the id, so no existing plan is migrated.
- No script may read the registry directly. Every read goes through `scripts/executors`.
- `scripts/run-codex-task.sh` and `scripts/run-codex-review.sh` keep their literal ladder block names and are not made registry-aware.
- Language is English throughout: code, comments, docs, commits, tests.
- Commit subjects are `<type>(<scope>): <subject>`, imperative, 50 characters or fewer, no trailing period.
- Every test command takes an explicit `timeout`, and every process a task starts is terminated before the task is complete.

## Contracts

**`scripts/executors`** — the only reader of the registry.
- `executors list` — one id per line for every valid entry, sorted; exit 0 even when the directory is empty or every entry is invalid.
- `executors get <id> <dotted.key>` — one field on stdout; an array prints one element per line; exit 0, or 1 when the id or key is absent.
- `executors path <id> <dotted.key>` — the field resolved absolute against the plugin root; same dotted-key syntax and same exits as `get`.
- Registry directory: `${DR_EXECUTORS_DIR:-<plugin-root>/reference/executors}`. The variable replaces the directory; it does not add to it.
- Exit 2 on a usage error or a missing `jq`.

**Registry entry schema** — `reference/executors/<id>.json`. Required: `id`, `locator`, `probe.command`, `probe.op`, `wrapper`, `session_dir`, `surfaces`, `blocks.gate`. Optional: `gate`, `reference`, `session_dir_env`, `blocks.assignment`, `blocks.successor`, `blocks.timeout`, `blocks.judge`, `reasons.not_enabled`, `reasons.logged_out`, `reasons.probe_failed`. An entry is valid when it parses as JSON, carries every required field, its `id` matches its filename stem, and no earlier entry claimed that id. An invalid entry is skipped by `list` with one diagnostic line on stderr.

**Executor id** — matches `^[a-z][a-z0-9-]*$`.

**Locator output grammar** — one line, exit 0 ok / 1 off / 2 error:
- `<id>-plugin ok version=<v> root=<path to end of line>`
- `<id>-plugin off reason=<token>`

**Probe contract** — reads one JSON object on stdin, prints one JSON object on stdout. Invoked as `node <probe.command resolved> <locator root>`. Request: `{"op": "<probe.op>", "cwd": "<native-form path>"}`. Response field read: `.authed` — `true`, `false`, or absent/null for a failed probe.

**`scripts/lib/executor-session.sh`** — sourced; defines functions only.
- `executor_session_id` — no argument; the value of `CLAUDE_CODE_SESSION_ID`.
- `executor_session_dir <id>` — `${<session_dir_env>:-$HOME/.claude/dr-superpowers/<session_dir>}`.
- `executor_session_file <id>` — `<dir>/<sid>.json`; returns 1 when there is no session id.
- `executor_session_on <id> <surface>` — succeeds only when that session file has that surface `true`.
- `executor_session_write <id> <json>` — atomic replace, then prune files older than 7 days in that directory.
- `executor_session_mark_off <id> <reason>` — writes `{session_id, usable:false, <each surface>:false, reason, checked_at, resets_at:null, resets_at_epoch:null, plugin_version:<preserved>}` and touches no other executor's file.

**`plan_executors FILE`** (in `scripts/lib/plan.sh`) — emits `<task number>\t<executor id>` for every task carrying an `**Executor:**` line outside a fenced block, in any `#### Part`. One row per task even when several parts carry a line; the first id wins.

**`plan_delegated FILE`** row kinds — `heavy`, `executor`, `total 4`. Precedence: `heavy` beats `executor`, `executor` beats `total 4`. The four-band threshold counts every total-4 task including those carrying an Executor line.

**Dispatch line marker** — `scripts/task-brief --header` renders an executor row as `Task <n> (executor)`.

**Ruling kinds** — `review-route --ruling` accepts `executor-empty-diff` and the legacy `codex-empty-diff`; each prints the spelling it was invoked with in its `ruling=` field.

**Reference path** — `reference/executor-lane.md` replaces `reference/external-executor.md`.

**Test fixture registry** — `tests/fixtures/executors/` holds `codex.json` (a copy of the shipped entry), `stub.json`, `opencode.json`, and `bin/` containing `stub-plugin` (locator), `stub-probe.mjs`, `stub-gate` and `stub-wrapper`. Suites point `DR_EXECUTORS_DIR` at it.

## Assumptions (evidence)

- `scripts/lib/task-state.sh`, `scripts/lib/task-execution.sh` and `scripts/repo-audit` contain no Codex reference and need no change — `grep -ci codex` returned 0 for each, 2026-09-20.
- `codex-session.sh` has exactly five callers — `scripts/codex-gate:19`, `scripts/plan-lint:18`, `scripts/review-route:27`, `scripts/run-codex-review.sh:24`, `tests/codex-gate.test.sh:236`, by grep 2026-09-20.
- `plan_scores` reports the highest total and risk across a split task's parts (`scripts/lib/plan.sh:137-138`), while `plan-lint` validates each `#### Part` independently (`scripts/plan-lint:200-209`), so a task can be `heavy` and carry a part-level Executor line at once.
- `review-route:205` echoes the ruling kind it was given, so canonicalising the legacy spelling would change an observable.
- `plan-lint:326-350` derives an inline plan's model and effort from `plan_delegated`, so Task 7 changes those verdicts; Task 9 adds the fixtures that pin the new behaviour.
- `run-codex-task.sh` never assigns `survivor=yes` — `grep -c` returned 0, 2026-09-20 — so `note=codex-may-still-be-running` is unreachable.
- `tests/run-codex-task.test.sh` asserts nothing on `note=` or the survivor path, so Task 12 must leave it untouched — grep 2026-09-20.
- The Codex review surface is off for this session (`codex-gate` printed `usable=true reason=ok review=false lane=false`), so plan review round 1 routes to a Claude seat and no task carries an `**Executor:**` line.
- unverified — Task 2 verifies that a stub locator and probe satisfy the Contracts grammar well enough for `detect-executors.sh` to produce a usable row for a fixture id.

## Task index

1. The registry helper and the Codex entry
2. The test fixture registry
3. The executor session library
4. Migrate the five session callers
5. Registry-driven roster in detect-executors.sh
6. plan-lint executor validation and the lane warning
7. plan_executors and the delegated set
8. task-brief renders the executor marker
9. plan-lint inline fixtures for the offload
10. review-route ruling kinds
11. Ownership release between consecutive offloads
12. Remove the unreachable survivor path
13. The executor-neutral reference
14. Repoint every reference link
15. The delegated-set definitions
16. The ruling kind and the ledger grammar
17. Generalise the recovery guide
18. Version bump and release

---

### Task 1: The registry helper and the Codex entry

**Files:**
- Create: `plugins/dr-superpowers/scripts/executors`
- Create: `plugins/dr-superpowers/reference/executors/codex.json`
- Test: `plugins/dr-superpowers/tests/executors.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the `scripts/executors` CLI, the registry schema and the executor-id pattern, all in Contracts. Every later task reads the registry through this helper.


**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/executors.test.sh`:

```bash
#!/usr/bin/env bash
# The registry is the one place an executor is described. A malformed entry
# must not remove every other executor from the roster: that is the silent
# downgrade detect-executors.sh was already written to avoid, and it is why
# list skips bad entries rather than failing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
EXEC="$P/scripts/executors"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
run() { DR_EXECUTORS_DIR="$1" bash "$EXEC" "${@:2}"; }

mkdir -p "$TMP/reg"
entry() { # entry <id> [extra jq assignment]
  jq -n --arg id "$1" '{id:$id, locator:"scripts/x-plugin",
    probe:{command:"scripts/lib/x-client.mjs", op:"auth"},
    wrapper:"scripts/run-x-task.sh", session_dir:($id + "-sessions"),
    surfaces:["lane"], blocks:{gate:"gate"}}' > "$TMP/reg/$1.json"
}
entry alpha
entry beta

check "script exists" "$([ -f "$EXEC" ] && echo yes || echo no)" "yes"

# --- list ------------------------------------------------------------------
check "list names every valid entry, sorted" "$(run "$TMP/reg" list | tr '\n' ' ')" "alpha beta "
check "list exits 0" "$(run "$TMP/reg" list >/dev/null; echo $?)" "0"
check "an empty directory lists nothing and still exits 0" \
  "$(mkdir -p "$TMP/empty"; run "$TMP/empty" list; echo "rc=$?")" "rc=0"

# --- get and path ----------------------------------------------------------
check "get reads a top-level field" "$(run "$TMP/reg" get alpha id)" "alpha"
check "get reads a dotted key" "$(run "$TMP/reg" get alpha probe.op)" "auth"
check "get prints an array one element per line" \
  "$(run "$TMP/reg" get alpha surfaces | tr '\n' ',')" "lane,"
check "get on an unknown id exits 1" "$(run "$TMP/reg" get nope id >/dev/null 2>&1; echo $?)" "1"
check "get on an unknown key exits 1" "$(run "$TMP/reg" get alpha nope >/dev/null 2>&1; echo $?)" "1"
check "path resolves against the plugin root" \
  "$(run "$TMP/reg" path alpha locator)" "$(cd "$P" && pwd)/scripts/x-plugin"
check "path takes a dotted key too" \
  "$(run "$TMP/reg" path alpha probe.command)" "$(cd "$P" && pwd)/scripts/lib/x-client.mjs"

# --- invalid entries are skipped, never fatal ------------------------------
# Each case keeps alpha and beta valid, so the assertion proves the bad entry
# was dropped rather than that the whole listing collapsed.
printf 'not json\n' > "$TMP/reg/broken.json"
check "malformed JSON is skipped" "$(run "$TMP/reg" list 2>/dev/null | tr '\n' ' ')" "alpha beta "
check "malformed JSON still exits 0" "$(run "$TMP/reg" list >/dev/null 2>&1; echo $?)" "0"
check "malformed JSON is reported on stderr" \
  "$(run "$TMP/reg" list 2>&1 >/dev/null | grep -c 'broken')" "1"
rm -f "$TMP/reg/broken.json"

jq -n '{id:"missing", locator:"scripts/x"}' > "$TMP/reg/missing.json"
check "a missing required field is skipped" "$(run "$TMP/reg" list 2>/dev/null | tr '\n' ' ')" "alpha beta "
rm -f "$TMP/reg/missing.json"

entry gamma; jq '.id = "delta"' "$TMP/reg/gamma.json" > "$TMP/x" && mv "$TMP/x" "$TMP/reg/gamma.json"
check "an id that disagrees with its filename is skipped" \
  "$(run "$TMP/reg" list 2>/dev/null | tr '\n' ' ')" "alpha beta "
rm -f "$TMP/reg/gamma.json"

jq -n '{id:"Alpha", locator:"a", probe:{command:"b", op:"auth"}, wrapper:"c",
        session_dir:"d", surfaces:["lane"], blocks:{gate:"gate"}}' > "$TMP/reg/Alpha.json"
check "an id outside the pattern is skipped" \
  "$(run "$TMP/reg" list 2>/dev/null | tr '\n' ' ')" "alpha beta "
rm -f "$TMP/reg/Alpha.json"

# --- the shipped entry -----------------------------------------------------
check "the shipped registry lists codex" \
  "$(bash "$EXEC" list | grep -cx codex)" "1"
check "the shipped codex entry names the real locator" \
  "$(bash "$EXEC" get codex locator)" "scripts/codex-plugin"
check "the shipped codex entry keeps the ladder block named gate" \
  "$(bash "$EXEC" get codex blocks.gate)" "gate"
check "the shipped codex entry keeps the session directory" \
  "$(bash "$EXEC" get codex session_dir)" "codex-sessions"
check "the shipped codex entry keeps the session directory override" \
  "$(bash "$EXEC" get codex session_dir_env)" "DR_CODEX_SESSION_DIR"
check "the shipped codex entry opens both surfaces" \
  "$(bash "$EXEC" get codex surfaces | tr '\n' ',')" "review,lane,"
check "the shipped codex entry names its wrapper" \
  "$(bash "$EXEC" get codex wrapper)" "scripts/run-codex-task.sh"
check "the shipped codex locator resolves to a real file" \
  "$([ -f "$(bash "$EXEC" path codex locator)" ] && echo yes || echo no)" "yes"
check "the shipped codex probe resolves to a real file" \
  "$([ -f "$(bash "$EXEC" path codex probe.command)" ] && echo yes || echo no)" "yes"

# --- usage -----------------------------------------------------------------
check "no arguments is a usage error" "$(bash "$EXEC" >/dev/null 2>&1; echo $?)" "2"
check "an unknown subcommand is a usage error" "$(bash "$EXEC" frobnicate >/dev/null 2>&1; echo $?)" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/executors.test.sh`
Expected: FAIL on "script exists" and every case after it, because `scripts/executors` does not exist.

- [ ] **Step 3: Write the registry entry**

Create `plugins/dr-superpowers/reference/executors/codex.json`:

```json
{
  "id": "codex",
  "locator": "scripts/codex-plugin",
  "probe": { "command": "scripts/lib/codex-client.mjs", "op": "auth" },
  "gate": "scripts/codex-gate",
  "wrapper": "scripts/run-codex-task.sh",
  "reference": "reference/executor-lane.md",
  "session_dir": "codex-sessions",
  "session_dir_env": "DR_CODEX_SESSION_DIR",
  "surfaces": ["review", "lane"],
  "blocks": {
    "gate": "gate",
    "assignment": "codex-assignment",
    "successor": "codex-successor",
    "timeout": "codex-timeout",
    "judge": "codex-judge"
  },
  "reasons": {
    "not_enabled": "the codex plugin is not enabled in this profile",
    "logged_out": "the codex plugin is installed but not logged in; run /codex:setup",
    "probe_failed": "the codex plugin auth probe failed; run /codex:setup"
  }
}
```

`reference` names `executor-lane.md`, which Task 13 creates. Nothing reads that
field before then, and Task 1's suite does not assert the file exists.

- [ ] **Step 4: Write the helper**

Create `plugins/dr-superpowers/scripts/executors`, mode 755:

```bash
#!/usr/bin/env bash
# Read the executor registry. Every other script reaches an executor's
# description through this one, so there is a single parser and a single
# definition of what makes an entry valid.
#
# An invalid entry is skipped rather than fatal. One malformed file must not
# empty the roster: a reader that sees no executors concludes no lane is
# available, which is the silent downgrade the roster was written to avoid.
#
# Usage: executors list
#        executors get  <id> <dotted.key>
#        executors path <id> <dotted.key>
# Exit: 0 answered; 1 unknown id or key; 2 usage error or missing jq.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DIR="${DR_EXECUTORS_DIR:-$ROOT/reference/executors}"

die() { printf 'executors: %s\n' "$1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
[ $# -ge 1 ] || die "usage: executors list | get <id> <key> | path <id> <key>"

# An entry is valid when it parses, carries every required field, its id
# matches the pattern, and its id matches its filename stem. The stem check is
# what lets `get` find an entry by id without scanning every file.
valid_entry() { # valid_entry <file> <stem>; prints the id when valid
  local file="$1" stem="$2" id
  id=$(jq -r '
    if (.id | type) != "string" then empty
    elif (.locator | type) != "string" then empty
    elif (.probe.command | type) != "string" then empty
    elif (.probe.op | type) != "string" then empty
    elif (.wrapper | type) != "string" then empty
    elif (.session_dir | type) != "string" then empty
    elif (.surfaces | type) != "array" then empty
    elif (.blocks.gate | type) != "string" then empty
    else .id end' "$file" 2>/dev/null | tr -d '\r') || return 1
  [ -n "$id" ] || { printf 'executors: %s: missing or malformed required fields\n' "$stem" >&2; return 1; }
  [[ "$id" =~ ^[a-z][a-z0-9-]*$ ]] || { printf 'executors: %s: id is not [a-z][a-z0-9-]*\n' "$id" >&2; return 1; }
  [ "$id" = "$stem" ] || { printf 'executors: %s.json: id is %s\n' "$stem" "$id" >&2; return 1; }
  printf '%s' "$id"
}

list_ids() { # one valid id per line, sorted, duplicates after the first dropped
  local file stem id seen=""
  [ -d "$DIR" ] || return 0
  for file in "$DIR"/*.json; do
    [ -e "$file" ] || continue
    stem=$(basename "$file" .json)
    id=$(valid_entry "$file" "$stem") || continue
    case " $seen " in
      *" $id "*) printf 'executors: %s: duplicate id, later entry ignored\n' "$id" >&2; continue ;;
    esac
    seen="$seen $id"
    printf '%s\n' "$id"
  done | sort
}

entry_file() { # entry_file <id>; prints the path when the id is valid
  local file="$DIR/$1.json"
  [ -f "$file" ] || return 1
  valid_entry "$file" "$1" >/dev/null || return 1
  printf '%s' "$file"
}

case "$1" in
  list)
    [ $# -eq 1 ] || die "usage: executors list"
    list_ids
    ;;
  get|path)
    [ $# -eq 3 ] || die "usage: executors $1 <id> <key>"
    file=$(entry_file "$2") || exit 1
    # getpath with a split key, so a dotted key reaches a nested field and a
    # plain key still works. `values` drops null, which is how an absent key
    # becomes exit 1 rather than the string "null".
    value=$(jq -r --arg k "$3" 'getpath($k | split(".")) | values
      | if type == "array" then .[] else . end' "$file" 2>/dev/null | tr -d '\r')
    [ -n "$value" ] || exit 1
    if [ "$1" = path ]; then
      case "$value" in /*|[A-Za-z]:*) printf '%s\n' "$value" ;; *) printf '%s/%s\n' "$ROOT" "$value" ;; esac
    else
      printf '%s\n' "$value"
    fi
    ;;
  *) die "unknown subcommand: $1" ;;
esac
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/executors.test.sh`
Expected: PASS, `26 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/executors plugins/dr-superpowers/reference/executors/codex.json plugins/dr-superpowers/tests/executors.test.sh
git commit -m "feat(superpowers): add the executor registry helper"
```

---

### Task 2: The test fixture registry

**Files:**
- Create: `plugins/dr-superpowers/tests/fixtures/executors/codex.json`
- Create: `plugins/dr-superpowers/tests/fixtures/executors/stub.json`
- Create: `plugins/dr-superpowers/tests/fixtures/executors/opencode.json`
- Create: `plugins/dr-superpowers/tests/fixtures/executors/bin/stub-plugin`
- Create: `plugins/dr-superpowers/tests/fixtures/executors/bin/stub-probe.mjs`
- Test: `plugins/dr-superpowers/tests/executors.test.sh` (append one block)

**Interfaces:**
- Consumes: the `scripts/executors` CLI and the registry schema (Contracts).
- Produces: the fixture registry directory, the stub locator and the stub probe (Contracts). Tasks 5, 6 and 10 point `DR_EXECUTORS_DIR` at it.


**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

The fixture directory holds a copy of `codex.json` because `DR_EXECUTORS_DIR`
replaces the shipped directory rather than adding to it. A fixture directory
holding only `stub` would hide `codex` from every suite that points at it,
and those suites assert Codex's behaviour is unchanged.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/executors.test.sh`, immediately before
the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- the shipped test fixture registry --------------------------------------
FIX="$HERE/fixtures/executors"
check "the fixture registry lists three ids" \
  "$(run "$FIX" list | tr '\n' ' ')" "codex opencode stub "
check "the fixture codex entry matches the shipped one" \
  "$(diff -q "$FIX/codex.json" "$P/reference/executors/codex.json" >/dev/null && echo same || echo differs)" "same"
check "the stub locator is executable" \
  "$([ -x "$FIX/bin/stub-plugin" ] && echo yes || echo no)" "yes"
check "the stub locator emits the ok grammar" \
  "$(bash "$FIX/bin/stub-plugin" | sed 's/root=.*/root=X/')" "stub-plugin ok version=0.0.0-stub root=X"
check "the stub locator exits 0 when ok" "$(bash "$FIX/bin/stub-plugin" >/dev/null; echo $?)" "0"
check "the stub locator can report off" \
  "$(STUB_LOCATOR=off bash "$FIX/bin/stub-plugin")" "stub-plugin off reason=plugin-not-enabled"
check "the stub locator exits 1 when off" \
  "$(STUB_LOCATOR=off bash "$FIX/bin/stub-plugin" >/dev/null; echo $?)" "1"
check "the stub probe answers authed" \
  "$(printf '{"op":"auth","cwd":"."}' | node "$FIX/bin/stub-probe.mjs" x | jq -r '.authed')" "true"
check "the stub probe can answer logged out" \
  "$(printf '{"op":"auth","cwd":"."}' | STUB_PROBE=logged-out node "$FIX/bin/stub-probe.mjs" x | jq -r '.authed')" "false"
check "the stub probe can fail without an authed field" \
  "$(printf '{"op":"auth","cwd":"."}' | STUB_PROBE=throw node "$FIX/bin/stub-probe.mjs" x | jq -r '.authed // "absent"')" "absent"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/executors.test.sh`
Expected: FAIL on "the fixture registry lists three ids", because the directory does not exist.

- [ ] **Step 3: Write the fixture entries**

Create `plugins/dr-superpowers/tests/fixtures/executors/codex.json` as a byte
copy of `plugins/dr-superpowers/reference/executors/codex.json`:

```bash
cp plugins/dr-superpowers/reference/executors/codex.json \
   plugins/dr-superpowers/tests/fixtures/executors/codex.json
```

Create `plugins/dr-superpowers/tests/fixtures/executors/stub.json`:

```json
{
  "id": "stub",
  "locator": "tests/fixtures/executors/bin/stub-plugin",
  "probe": { "command": "tests/fixtures/executors/bin/stub-probe.mjs", "op": "auth" },
  "gate": "tests/fixtures/executors/bin/stub-gate",
  "wrapper": "tests/fixtures/executors/bin/stub-wrapper",
  "reference": "reference/executor-lane.md",
  "session_dir": "stub-sessions",
  "session_dir_env": "DR_STUB_SESSION_DIR",
  "surfaces": ["lane"],
  "blocks": {
    "gate": "stub-gate",
    "assignment": "stub-assignment",
    "successor": "stub-successor",
    "timeout": "stub-timeout"
  },
  "reasons": {
    "not_enabled": "the stub executor is not enabled in this profile",
    "logged_out": "the stub executor is not logged in; run /stub:setup",
    "probe_failed": "the stub executor auth probe failed; run /stub:setup"
  }
}
```

Create `plugins/dr-superpowers/tests/fixtures/executors/opencode.json`, whose
only purpose is to prove a registered id suppresses its PATH-probe row:

```json
{
  "id": "opencode",
  "locator": "tests/fixtures/executors/bin/stub-plugin",
  "probe": { "command": "tests/fixtures/executors/bin/stub-probe.mjs", "op": "auth" },
  "wrapper": "tests/fixtures/executors/bin/stub-wrapper",
  "session_dir": "opencode-sessions",
  "surfaces": ["lane"],
  "blocks": { "gate": "stub-gate", "assignment": "stub-assignment" }
}
```

- [ ] **Step 4: Write the stub locator**

Create `plugins/dr-superpowers/tests/fixtures/executors/bin/stub-plugin`, mode 755:

```bash
#!/usr/bin/env bash
# Stub locator satisfying the Contracts grammar. STUB_LOCATOR picks the branch.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${STUB_LOCATOR:-ok}" in
  off) printf 'stub-plugin off reason=plugin-not-enabled\n'; exit 1 ;;
  missing) printf 'stub-plugin off reason=plugin-missing\n'; exit 1 ;;
  *) printf 'stub-plugin ok version=0.0.0-stub root=%s\n' "$HERE"; exit 0 ;;
esac
```

- [ ] **Step 5: Write the stub probe**

Create `plugins/dr-superpowers/tests/fixtures/executors/bin/stub-probe.mjs`:

```javascript
// Stub auth probe satisfying the Contracts probe contract. STUB_PROBE picks
// the branch: ok, logged-out, or throw (a probe that answers without .authed,
// which the roster must read as probe_failed rather than as logged out).
import process from "node:process";

let raw = "";
for await (const chunk of process.stdin) raw += chunk;
let request = {};
try {
  request = JSON.parse(raw);
} catch {
  request = {};
}

const mode = process.env.STUB_PROBE || "ok";
const answer = { op: request.op ?? null, cwd: request.cwd ?? null };

if (mode === "throw") {
  answer.reason = "stub: probe exploded";
} else {
  answer.authed = mode !== "logged-out";
  answer.reason = answer.authed ? null : "logged-out";
}

process.stdout.write(`${JSON.stringify(answer)}\n`);
```

The probe echoes `op` and `cwd` back. Task 5's suite reads `cwd` from it to
prove the roster converts the working directory to native form before
handing it over.

- [ ] **Step 6: Write the stub gate and wrapper**

Create `plugins/dr-superpowers/tests/fixtures/executors/bin/stub-gate`, mode 755:

```bash
#!/usr/bin/env bash
# Stub gate. Nothing in this sub-project runs it; the registry names it so a
# reader can prove the field resolves, and Task 5 asserts the path exists.
set -uo pipefail
printf 'stub-gate usable=true reason=ok lane=%s resets_at=- source=probe\n' "${STUB_GATE_LANE:-false}"
```

Create `plugins/dr-superpowers/tests/fixtures/executors/bin/stub-wrapper`, mode 755:

```bash
#!/usr/bin/env bash
# Stub wrapper. Its existence is what makes the stub id lane-implemented in
# detect-executors.sh; no suite in this sub-project runs it.
set -uo pipefail
printf 'stub - status=DONE exit=0 commits=0000000..0000000 thread=stub report=-\n'
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/executors.test.sh`
Expected: PASS, `36 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/tests/fixtures/executors plugins/dr-superpowers/tests/executors.test.sh
git commit -m "test(superpowers): add the fixture executor registry"
```

---

### Task 3: The executor session library

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/executor-session.sh`
- Test: `plugins/dr-superpowers/tests/executor-session.test.sh`

**Interfaces:**
- Consumes: the `scripts/executors` CLI (Contracts) for `session_dir`, `session_dir_env` and `surfaces`.
- Produces: the six `executor_session_*` functions (Contracts). Task 4 migrates the five callers onto them.


**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/executor-session.test.sh`:

```bash
#!/usr/bin/env bash
# Session state is per executor. The failure this guards is cross-talk: one
# executor hitting a rate limit must not mark another's surfaces off, because
# review-route and plan-lint both read those files.
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

export DR_EXECUTORS_DIR="$HERE/fixtures/executors"
export CLAUDE_CODE_SESSION_ID=session-test
export DR_CODEX_SESSION_DIR="$TMP/codex" DR_STUB_SESSION_DIR="$TMP/stub"
. "$P/scripts/lib/executor-session.sh"

check "the session id comes from the environment" "$(executor_session_id)" "session-test"
check "a directory honours its override" "$(executor_session_dir codex)" "$TMP/codex"
check "another executor has its own directory" "$(executor_session_dir stub)" "$TMP/stub"
check "the two directories differ" \
  "$([ "$(executor_session_dir codex)" != "$(executor_session_dir stub)" ] && echo yes || echo no)" "yes"
check "the file is the session id under that directory" \
  "$(executor_session_file codex)" "$TMP/codex/session-test.json"

# --- surfaces --------------------------------------------------------------
executor_session_write codex '{"session_id":"session-test","usable":true,"review":true,"lane":false}'
check "an open surface reads on" "$(executor_session_on codex review && echo on || echo off)" "on"
check "a closed surface reads off" "$(executor_session_on codex lane && echo on || echo off)" "off"
check "an absent executor reads off" "$(executor_session_on stub lane && echo on || echo off)" "off"

# --- mark_off writes the record the gate reads back ------------------------
executor_session_write codex '{"session_id":"session-test","usable":true,"review":true,"lane":true,"plugin_version":"1.0.3"}'
executor_session_mark_off codex quota
rec="$TMP/codex/session-test.json"
check "mark_off clears usable" "$(jq -r '.usable' "$rec")" "false"
check "mark_off clears every surface in the registry" \
  "$(jq -r '[.review, .lane] | join(",")' "$rec")" "false,false"
check "mark_off records the reason" "$(jq -r '.reason' "$rec")" "quota"
check "mark_off records the session id" "$(jq -r '.session_id' "$rec")" "session-test"
check "mark_off stamps checked_at" "$(jq -r '.checked_at | test("^[0-9]{4}-")' "$rec")" "true"
check "mark_off nulls both reset fields" \
  "$(jq -r '[.resets_at, .resets_at_epoch] | join(",")' "$rec")" "null,null"
check "mark_off preserves plugin_version" "$(jq -r '.plugin_version' "$rec")" "1.0.3"

# --- no cross-talk ---------------------------------------------------------
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true}'
executor_session_mark_off codex quota
check "marking one executor off leaves another untouched" \
  "$(executor_session_on stub lane && echo on || echo off)" "on"

# --- no session id ---------------------------------------------------------
check "without a session id the file call fails" \
  "$(CLAUDE_CODE_SESSION_ID= ; executor_session_file codex >/dev/null 2>&1; echo $?)" "1"
check "without a session id a surface reads off" \
  "$(CLAUDE_CODE_SESSION_ID= ; executor_session_on codex review && echo on || echo off)" "off"

# --- pruning ---------------------------------------------------------------
touch -d '8 days ago' "$TMP/codex/ancient.json" 2>/dev/null || touch -t 200001010000 "$TMP/codex/ancient.json"
executor_session_write codex '{"session_id":"session-test","usable":true}'
check "a week-old session file is pruned on write" \
  "$([ -f "$TMP/codex/ancient.json" ] && echo kept || echo pruned)" "pruned"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/executor-session.test.sh`
Expected: FAIL — the source line reports `No such file or directory` and every case fails.

- [ ] **Step 3: Write the library**

Create `plugins/dr-superpowers/scripts/lib/executor-session.sh`:

```bash
# Per-executor session state: one file per Claude Code session per executor,
# written by that executor's gate and marked off by a runner that hits a
# quota or a rate limit.
#
# The file is keyed by session id rather than kept in the project: a quota is
# account-wide, so the answer belongs to the session, not to any one project
# the session works in. Readers fail closed - any state that is not a positive
# answer for this session is off.
#
# Every function takes the executor id first. One shared file would mean one
# executor's mark-off closing another's surfaces, and review-route and
# plan-lint both read these files.
#
# Source this file; it defines functions only.

_EXECUTOR_SESSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_executor_session_field() { # _executor_session_field <id> <key>
  bash "$_EXECUTOR_SESSION_LIB_DIR/../executors" get "$1" "$2" 2>/dev/null
}

executor_session_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

# The override variable is named by the registry, so an executor keeps whatever
# name its callers already export - DR_CODEX_SESSION_DIR, for Codex.
executor_session_dir() { # executor_session_dir <id>
  local env_name override dir
  env_name=$(_executor_session_field "$1" session_dir_env)
  if [ -n "$env_name" ]; then
    override=${!env_name:-}
    [ -z "$override" ] || { printf '%s' "$override"; return 0; }
  fi
  dir=$(_executor_session_field "$1" session_dir)
  [ -n "$dir" ] || return 1
  printf '%s/.claude/dr-superpowers/%s' "$HOME" "$dir"
}

# executor_session_file <id> - this session's file; fails with no session id.
executor_session_file() {
  local sid dir; sid=$(executor_session_id)
  [ -n "$sid" ] || return 1
  dir=$(executor_session_dir "$1") || return 1
  printf '%s/%s.json' "$dir" "$sid"
}

# executor_session_on <id> <surface> - succeeds only when this session's gate
# said that surface may be used.
executor_session_on() {
  local f; f=$(executor_session_file "$1") || return 1
  [ "$(jq -r --arg s "$2" '.[$s] == true' "$f" 2>/dev/null | tr -d '\r')" = true ]
}

# executor_session_write <id> <json> - replace this session's file in one
# rename, so a concurrent reader never sees half a file, and prune week-old
# sessions for this executor only.
executor_session_write() {
  local f dir; f=$(executor_session_file "$1") || return 0
  dir=$(executor_session_dir "$1") || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$2" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"
  find "$dir" -maxdepth 1 -name '*.json' -mtime +7 -delete 2>/dev/null || true
}

# executor_session_mark_off <id> <reason> - this executor is unusable for the
# rest of the session: no reset time, so the gate's cache keeps the answer.
#
# Every surface the registry lists is cleared, and the metadata fields the
# gate reads back out of the cache are written: reason, checked_at, both
# resets_at fields, and whatever plugin_version the prior file carried.
executor_session_mark_off() {
  local f prior surfaces; f=$(executor_session_file "$1") || return 0
  # Parsed, not cat: an empty or torn file would make the jq below produce
  # nothing, and the empty file that writes reads back as a cache miss, so the
  # next gate call re-probes and can turn the executor on again.
  prior=$(jq -c . "$f" 2>/dev/null) || prior=''
  [ -n "$prior" ] || prior='{}'
  surfaces=$(_executor_session_field "$1" surfaces | jq -R . | jq -sc .)
  [ -n "$surfaces" ] || surfaces='[]'
  executor_session_write "$1" "$(jq -c \
    --arg sid "$(executor_session_id)" --arg r "$2" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson surfaces "$surfaces" '
    {session_id: $sid, usable: false, reason: $r, checked_at: $at,
     resets_at: null, resets_at_epoch: null,
     plugin_version: (.plugin_version // null)}
    + (reduce $surfaces[] as $s ({}; . + {($s): false}))' <<<"$prior" 2>/dev/null)"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/executor-session.test.sh`
Expected: PASS, `20 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/executor-session.sh plugins/dr-superpowers/tests/executor-session.test.sh
git commit -m "feat(superpowers): add per-executor session state"
```

---

### Task 4: Migrate the five session callers

**Files:**
- Modify: `plugins/dr-superpowers/scripts/codex-gate:19` and its `codex_session_*` call sites
- Modify: `plugins/dr-superpowers/scripts/plan-lint:18` and its `codex_session_on` call site
- Modify: `plugins/dr-superpowers/scripts/review-route:27` and its `codex_session_on` call sites
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh:24` and its `codex_session_*` call sites
- Modify: `plugins/dr-superpowers/tests/codex-gate.test.sh:236-247` (harness lines only)
- Delete: `plugins/dr-superpowers/scripts/lib/codex-session.sh`

**Interfaces:**
- Consumes: the six `executor_session_*` functions (Contracts).
- Produces: nothing new. After this task no file references `codex-session.sh`.


**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

Codex's behaviour must not move. Every call gains the literal id `codex` as its
first argument and nothing else changes. The old library is deleted rather than
shimmed: two ways to reach one state is the ambiguity this sub-project removes.

- [ ] **Step 1: Record the pre-change behaviour**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/codex-gate.test.sh | tail -1`
Expected: `54 passed, 0 failed`. Note the number; Step 6 must reproduce it exactly.

- [ ] **Step 2: Repoint the four scripts**

In each of `scripts/codex-gate`, `scripts/plan-lint`, `scripts/review-route`
and `scripts/run-codex-review.sh`, replace the source line

```bash
. "$HERE/lib/codex-session.sh"
```

with

```bash
. "$HERE/lib/executor-session.sh"
```

Then rename every call in those four files, adding `codex` as the first
argument:

| Old call | New call |
|---|---|
| `codex_session_id` | `executor_session_id` |
| `codex_session_file` | `executor_session_file codex` |
| `codex_session_on <surface>` | `executor_session_on codex <surface>` |
| `codex_session_write <json>` | `executor_session_write codex <json>` |
| `codex_session_mark_off <reason>` | `executor_session_mark_off codex <reason>` |

`executor_session_id` takes no id, because the session id is the harness's, not
the executor's.

Find every call site with:

```bash
grep -rn 'codex_session_' scripts/
```

Expected after the rename: no output.

- [ ] **Step 3: Repoint the test harness**

In `plugins/dr-superpowers/tests/codex-gate.test.sh`, replace the source line
at 236

```bash
. "$P/scripts/lib/codex-session.sh"
```

with

```bash
export DR_EXECUTORS_DIR="$HERE/fixtures/executors"
. "$P/scripts/lib/executor-session.sh"
```

and rename the two calls in the helper and the mark-off case:

```bash
  if executor_session_on codex "$2"; then check "$1" on "$3"; else check "$1" off "$3"; fi
```

```bash
executor_session_mark_off codex quota
```

**Change no `check` line.** The assertions are the record that Codex's
behaviour did not move; only the harness around them changes.

- [ ] **Step 4: Delete the old library**

```bash
git rm plugins/dr-superpowers/scripts/lib/codex-session.sh
```

- [ ] **Step 5: Prove nothing references it**

Run: `cd plugins/dr-superpowers && grep -rn 'codex-session' . --exclude-dir=.git`
Expected: no output.

- [ ] **Step 6: Run the affected suites**

Run each, with the expected tail:

```bash
cd plugins/dr-superpowers
timeout 300 bash tests/codex-gate.test.sh     | tail -1   # 54 passed, 0 failed
timeout 300 bash tests/codex-review.test.sh   | tail -1   # 88 passed, 0 failed
timeout 300 bash tests/review-route.test.sh   | tail -1   # 181 passed, 0 failed
timeout 300 bash tests/executor-session.test.sh | tail -1 # 20 passed, 0 failed
```

Expected: every line reports `0 failed`, and `codex-gate.test.sh` reports the
same count as Step 1.

- [ ] **Step 7: Commit**

```bash
git add -A plugins/dr-superpowers/scripts plugins/dr-superpowers/tests/codex-gate.test.sh
git commit -m "refactor(superpowers): key session state by executor"
```

---

### Task 5: Registry-driven roster in detect-executors.sh

**Files:**
- Modify: `plugins/dr-superpowers/scripts/detect-executors.sh`
- Test: `plugins/dr-superpowers/tests/detect.test.sh` (append one block)

**Interfaces:**
- Consumes: the `scripts/executors` CLI, the locator grammar, the probe contract and the fixture registry (all in Contracts).
- Produces: nothing new. The roster's JSON shape is unchanged.


**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/detect.test.sh`, immediately before the
final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- the roster is driven by the registry ----------------------------------
# A registry id is probed through its own locator and probe, and its reasons
# come from its entry. A registered id must also suppress its PATH-probe row:
# two rows with one id would break every consumer that selects by id.
FIXREG="$HERE/fixtures/executors"
regrun() { PATH="$TMP/bin" CLAUDE_CONFIG_DIR="$TMP/config" CLAUDE_PROJECT_DIR= \
           DR_CODEX_POLICY="$TMP/policy.json" DR_EXECUTORS_DIR="$FIXREG" \
           STUB_MODE="${STUB_MODE:-ok}" "$BASH_BIN" "$SCRIPT"; }

out=$(regrun)
check "the stub executor appears in the roster" "$(field stub present "$out")" "true"
check "the stub executor is usable" "$(field stub usable "$out")" "true"
check "the stub executor is batch capable by virtue of its wrapper" \
  "$(field stub batch_capable "$out")" "true"
check "a usable registry executor carries no reason" "$(field stub reason "$out")" "null"
check "the stub row's path is its locator root" \
  "$(field stub path "$out" | grep -c 'fixtures/executors')" "1"

out=$(STUB_LOCATOR=off regrun)
check "a locator that reports off is not present" "$(field stub present "$out")" "false"
check "an off locator uses the entry's not_enabled reason" \
  "$(field stub reason "$out")" "the stub executor is not enabled in this profile"

out=$(STUB_PROBE=logged-out regrun)
check "a logged-out probe is explicit" "$(field stub auth_status "$out")" "logged_out"
check "a logged-out executor is not usable" "$(field stub usable "$out")" "false"
check "a logged-out executor uses the entry's remedy" \
  "$(field stub reason "$out" | grep -c '/stub:setup')" "1"

out=$(STUB_PROBE=throw regrun)
check "a probe without authed is a failed probe" "$(field stub auth_status "$out")" "probe_failed"
check "a failed probe uses the entry's probe_failed reason" \
  "$(field stub reason "$out" | grep -c '/stub:setup')" "1"

# A registered id suppresses its PATH row even when the binary is on PATH.
make_stub opencode "opencode 1.0.0"
out=$(regrun)
check "a registered id yields exactly one row" \
  "$(jq '[.[] | select(.id == "opencode")] | length' <<<"$out")" "1"
check "the registered opencode row is lane-implemented" \
  "$(field opencode usable "$out")" "true"
rm -f "$TMP/bin/opencode"

# An unregistered batch-capable id keeps the PATH probe and its missing-lane
# reason, which must name the registry rather than assert codex is unique.
make_stub cursor-agent "cursor-agent 1.0.0"
out=$(regrun)
check "an unregistered id is still not usable" "$(field cursor-agent usable "$out")" "false"
check "the missing-lane reason names the registry" \
  "$(field cursor-agent reason "$out" | grep -c 'executors list')" "1"
rm -f "$TMP/bin/cursor-agent"

# The probe receives a native-form cwd, as the codex probe does.
: > "$TMP/probe-cwd.log"
STUB_PROBE_LOG="$TMP/probe-cwd.log" regrun >/dev/null
expected_cwd="$PWD"
command -v cygpath >/dev/null 2>&1 && expected_cwd=$(cygpath -m "$PWD")
check "a registry probe receives a native-form cwd" \
  "$(head -1 "$TMP/probe-cwd.log")" "$expected_cwd"
```

For the last case the stub probe records what it was given. Add to
`plugins/dr-superpowers/tests/fixtures/executors/bin/stub-probe.mjs`, directly
before its final `process.stdout.write` line:

```javascript
if (process.env.STUB_PROBE_LOG) {
  const { appendFileSync } = await import("node:fs");
  try {
    appendFileSync(process.env.STUB_PROBE_LOG, `${request.cwd ?? "-"}\n`);
  } catch {
    // A test that cannot write its own log fails on the assertion instead.
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/detect.test.sh 2>&1 | grep -c '^FAIL'`
Expected: a non-zero count — the stub id is absent from the roster entirely.

- [ ] **Step 3: Rewrite the emit branch**

In `plugins/dr-superpowers/scripts/detect-executors.sh`, replace the whole
`if [ "$id" = codex ]` block inside `emit` — from that line to its matching
`else` — with a registry-driven branch. The function's signature loses its
`lane_implemented` argument, which the registry now answers:

```bash
emit() { # emit <id> <batch_capable> <incapable_reason>
  local id="$1" capable="$2" incapable_reason="$3"
  local path present version authed reason usable auth_status=not_applicable
  local registered=no entry_reason

  # A registry id is reached only through its own locator and probe: presence,
  # version and login state come from them, never from a PATH probe. Every
  # other id keeps the PATH probe, because no registry entry owns it.
  if bash "$HERE/executors" get "$id" id >/dev/null 2>&1; then
    registered=yes
    path=""
    present=false
    version=null
    authed=null
    auth_status=not_applicable
    local locator probe_cmd probe_op locator_line locator_root auth_json
    locator=$(bash "$HERE/executors" path "$id" locator 2>/dev/null)
    probe_cmd=$(bash "$HERE/executors" path "$id" probe.command 2>/dev/null)
    probe_op=$(bash "$HERE/executors" get "$id" probe.op 2>/dev/null)
    if [ -n "$locator" ] && locator_line=$(bash "$locator" 2>/dev/null); then
      present=true
      locator_root=${locator_line#*root=}
      path=$locator_root
      version=$(jq -Rn --arg v "${locator_line#*version=}" '$v | sub(" root=.*"; "")')
      auth_json=$(printf '{"op":"%s","cwd":"%s"}' "$probe_op" "$(dr_native_path "$PWD")" \
        | timeout 60 node "$probe_cmd" "$locator_root" 2>/dev/null)
      case "$(jq -r '.authed | tojson' <<<"${auth_json:-{\}}" 2>/dev/null)" in
        true)  authed=true;  auth_status=authenticated ;;
        false) authed=false; auth_status=logged_out ;;
        *)     authed=null;  auth_status=probe_failed ;;
      esac
    fi
  else
    path=$(command -v "$id" 2>/dev/null || true)
    if [ -n "$path" ]; then present=true; else present=false; fi
    version=null
    if [ "$present" = true ]; then
      local v
      v=$(timeout 20 "$id" --version 2>/dev/null | head -1 | tr -d '\r')
      [ -n "$v" ] && version=$(jq -Rn --arg v "$v" '$v')
    fi
    authed=null
  fi

  usable=false
  reason=null
  entry_reason() { bash "$HERE/executors" get "$id" "reasons.$1" 2>/dev/null; }
  if [ "$present" != true ]; then
    if [ "$registered" = yes ]; then
      reason=$(jq -Rn --arg r "$(entry_reason not_enabled)" '$r')
    else
      reason='"not on PATH"'
    fi
  elif [ "$capable" != true ]; then
    reason=$(jq -Rn --arg r "$incapable_reason" '$r')
  elif [ "$registered" != yes ]; then
    reason=$(jq -Rn --arg r "no executor lane is implemented for $id in this plugin; run 'executors list' for the registered executors" '$r')
  elif [ ! -r "$(bash "$HERE/executors" path "$id" wrapper 2>/dev/null)" ]; then
    # Registered but broken: an installation fault rather than an executor
    # state, so the message is generated rather than taken from the map.
    reason=$(jq -Rn --arg r "the $id executor is registered but its wrapper is missing" '$r')
  elif [ "$authed" = false ]; then
    reason=$(jq -Rn --arg r "$(entry_reason logged_out)" '$r')
  elif [ "$auth_status" = probe_failed ]; then
    reason=$(jq -Rn --arg r "$(entry_reason probe_failed)" '$r')
  elif [ "$version" = null ] && [ "$registered" != yes ]; then
    reason='"version probe failed; check the CLI installation"'
  else
    usable=true
  fi

  jq -n \
    --arg id "$id" \
    --argjson present "$present" \
    --argjson version "$version" \
    --argjson authed "$authed" \
    --arg auth_status "$auth_status" \
    --argjson batch_capable "$capable" \
    --argjson usable "$usable" \
    --argjson reason "$reason" \
    --arg path "$path" \
    '{id:$id, present:$present, path:(if $path=="" then null else $path end),
      version:$version, authed:$authed, auth_status:$auth_status, batch_capable:$batch_capable,
      usable:$usable, reason:$reason}'
}
```

A registered id is `batch_capable` by definition and its version is whatever
the locator reported, so the `version = null` check applies only to PATH ids.

- [ ] **Step 4: Drive the roster from the registry**

Replace the dispatch block at the foot of the file with one that emits every
registry id first and then the PATH ids that no registry entry claimed:

```bash
{
  registered=$(bash "$HERE/executors" list 2>/dev/null)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    emit "$id" true ""
  done <<<"$registered"

  # Ids with no registry entry. Each is skipped when registered, so a second
  # executor never produces two rows under one id.
  path_row() { grep -qxF "$1" <<<"$registered" || emit "$1" "$2" "$3"; }
  path_row cursor-agent true ""
  path_row opencode true ""
  path_row antigravity false "installed, but its only agent mode (antigravity chat -m agent) opens a GUI editor session with no output file, no completion signal, and no exit code tied to the work"
} | jq -s '.'
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/detect.test.sh | tail -1`
Expected: `59 passed, 0 failed`, with every pre-existing assertion still passing.

- [ ] **Step 6: Confirm the live Codex row is unchanged**

Run: `cd D:/Repositories/Personal/darkraise-ai-plugins && timeout 120 bash plugins/dr-superpowers/scripts/detect-executors.sh | jq -c '.[] | select(.id=="codex")'`
Expected: `present: true`, `version: "1.0.3"`, `authed: true`, `auth_status: "authenticated"`, `usable: true`, `reason: null` — identical to before this task.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/detect-executors.sh plugins/dr-superpowers/tests/detect.test.sh plugins/dr-superpowers/tests/fixtures/executors/bin/stub-probe.mjs
git commit -m "refactor(superpowers): drive the roster from the registry"
```

---

### Task 6: plan-lint executor validation and the lane warning

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint:191-194` (block resolution), `:272-284` (the Executor branch and the lane candidate), `:294-308` (the warning)
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh` (append one block)

**Interfaces:**
- Consumes: the `scripts/executors` CLI and `executor_session_on` (Contracts).
- Produces: nothing new.


**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

Two independent paths touch executors and they have different predicates. The
Executor-line validation keys on the line's own id. The lane-eligible warning
keys on session state and the roster, never on the header tick — `p1.md` at
`tests/plan-lint.test.sh:416-420` carries no header tick and still expects the
warning.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/plan-lint.test.sh`, immediately before
its final summary line:

```bash
# --- Executor lines are validated against their own executor ----------------
export DR_EXECUTORS_DIR="$HERE/fixtures/executors"

# A stub Executor line validates against the stub's own blocks. The fixture
# ladder supplies them, so the shipped ladder is untouched.
variant s1.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** stub stub-model \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** stub/'
lint s1.md
lacks "a stub Executor line is accepted" "$out" "ERROR Task 1"

# An id with no registry entry is rejected, naming the registry.
variant s2.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** nosuch m \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** nosuch/'
lint s2.md
has "an unregistered Executor id is an error" "$out" "ERROR Task 1: Executor names no registered executor: nosuch (run 'executors list')"

# The header must name the line's own id, not merely some executor.
variant s3.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** stub stub-model \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
lint s3.md
has "the header must name the line's executor" "$out" "ERROR Task 1: Executor used but the header's '> **External executors:**' line does not name stub"
```

Add the fixture ladder blocks the stub validates against. Create
`plugins/dr-superpowers/tests/fixtures/stub-ladder.md`:

```markdown
# Fixture ladder for the stub executor

```stub-gate
min_score 2
max_risk 1
require_rule_s_clean true
require_external_enabled true
```

```stub-assignment
2 stub-model medium
3 stub-model high
4 stub-model high
```
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/plan-lint.test.sh 2>&1 | grep '^FAIL' | head -3`
Expected: the three new assertions fail — a `stub` line is rejected because the
current code compares it against `codex-assignment`.

- [ ] **Step 3: Resolve blocks per executor**

In `plugins/dr-superpowers/scripts/plan-lint`, replace lines 191-193

```bash
gate=$(ladder_block gate)
min_score=$(awk '$1 == "min_score" { print $2 }' <<<"$gate")
max_risk=$(awk '$1 == "max_risk" { print $2 }' <<<"$gate")
```

with a helper that reads an executor's own blocks, defaulting to Codex's so
every existing call keeps its values:

```bash
# An executor's gate and assignment blocks are named by its registry entry.
# Codex's gate block is literally called `gate`, so nothing moves for it.
executor_field() { bash "$HERE/executors" get "$1" "$2" 2>/dev/null; }
executor_gate() { # executor_gate <id> <min_score|max_risk>
  local block; block=$(executor_field "$1" blocks.gate)
  [ -n "$block" ] || return 1
  awk -v k="$2" '$1 == k { print $2 }' <<<"$(ladder_block "$block")"
}
executor_rung() { # executor_rung <id> <total>
  local block; block=$(executor_field "$1" blocks.assignment)
  [ -n "$block" ] || return 1
  awk -v t="$2" '$1 == t { print $2 " / " $3 }' <<<"$(ladder_block "$block")"
}
min_score=$(executor_gate codex min_score)
max_risk=$(executor_gate codex max_risk)
```

- [ ] **Step 4: Validate the Executor line against its own id**

Replace the Executor branch at lines 272-284 with:

```bash
    executor=$(line Executor)
    if [ -n "$executor" ]; then
      eid=$(sed -E 's/^\*\*Executor:\*\*[[:space:]]*([^[:space:]]+).*/\1/' <<<"$executor")
      [ "$sev" = ERROR ] || say ERROR "$where" "an Executor line on an overridden task fails the lane gate"
      if ! bash "$HERE/executors" get "$eid" id >/dev/null 2>&1; then
        say ERROR "$where" "Executor names no registered executor: $eid (run 'executors list')"
      else
        emin=$(executor_gate "$eid" min_score) emax=$(executor_gate "$eid" max_risk)
        { [ "$t" -ge "${emin:-0}" ] && [ "$d" -le "${emax:-3}" ]; } \
          || say ERROR "$where" "total $t / risk $d fails the lane gate (min_score ${emin:-0}, max_risk ${emax:-3})"
        rung=$(executor_rung "$eid" "$t")
        { [ -n "$rung" ] && [[ "$executor" == *"$eid $rung"* ]]; } || say ERROR "$where" "Executor does not name the $eid-assignment rung for total $t ($eid ${rung:-none})"
        [[ "$externals" == *"$eid"* ]] || say ERROR "$where" "Executor used but the header's '> **External executors:**' line does not name $eid"
      fi
    elif [ "$sev" = ERROR ] && [ $((a + b + c)) -lt 4 ] && [ "$b" -lt 3 ] \
         && [ "$t" -ge "$min_score" ] && [ "$d" -le "$max_risk" ]; then
      rung=$(executor_rung codex "$t")
      [ -z "$rung" ] || lane="$lane$where"$'\t'"$rung"$'\n'
    fi
```

The four ERROR messages keep their wording with the id substituted, so a Codex
plan's output is byte-identical. The `codex-assignment` string that was
hardcoded becomes `$eid-assignment` in the third message, which for Codex reads
exactly as before.

- [ ] **Step 5: Generalise the warning without changing its predicate**

Replace lines 294-303 — the comment and the `if` — with:

```bash
# The lane probe is lazy: the detector costs about two seconds, so it runs only
# when some task could have taken the lane and did not, and only when this
# session's gate opened that executor's lane surface. A plan without Executor
# lines is correct on a machine where no executor is usable, so every outcome
# other than a usable roster row prints nothing. Inline plans are skipped: an
# inline plan may now carry Executor lines, so this warning would be
# meaningful there, but turning it on changes a pinned fixture for an advisory
# message. That is a deliberate deferral, recorded in the register, not an
# oversight.
if [ -n "$lane" ] && [ "$probe" -eq 1 ] && [ "$mode" != inline ] && executor_session_on codex lane; then
```

The predicate is unchanged: session lane surface, plus a usable roster row,
plus a lazy probe, plus non-inline mode. It never reads the header tick, which
is why `p1.md` keeps warning.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/plan-lint.test.sh | tail -1`
Expected: `0 failed`, with every pre-existing assertion unchanged.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/tests/plan-lint.test.sh plugins/dr-superpowers/tests/fixtures/stub-ladder.md
git commit -m "refactor(superpowers): validate Executor lines per executor"
```

---

### Task 7: plan_executors and the delegated set

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/plan.sh` (add `plan_executors`, extend `plan_delegated`)
- Test: `plugins/dr-superpowers/tests/plan-lib.test.sh` (append one block)

**Interfaces:**
- Consumes: nothing.
- Produces: `plan_executors FILE` and the `executor` row kind with its precedence rules (Contracts). Task 8 renders the row; Task 6's lint reads the same Executor lines.


**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

`heavy` beats `executor` because the `(heavy)` label is what
`executing-plans/SKILL.md:169-171` keys the preflight ruling on. A split task
can be both: `plan-lint` validates each part independently while `plan_scores`
reports the highest total and risk across parts.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/plan-lib.test.sh`, before its summary:

```bash
# --- plan_executors ---------------------------------------------------------
sed 's/^|//' > "$TMP/exec.md" <<'EOF'
|# Executors Fixture
|
|### Task 1: plain
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: offloaded
|
|**Implementer:** dr-superpowers:impl-sonnet-medium
|**Executor:** codex gpt-5.5 / medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 3: fenced only
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|```markdown
|**Executor:** codex gpt-5.5 / medium
|```
|
|### Task 4: split, executor on part A, heavy part B
|
|#### Part A: cheap
|
|**Implementer:** dr-superpowers:impl-sonnet-medium
|**Executor:** codex gpt-5.5 / medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|#### Part B: risky
|
|**Implementer:** dr-superpowers:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
EOF

check "plan_executors names an offloaded task" \
  "$(plan_executors "$TMP/exec.md" | awk -F'\t' '$1 == 2 { print $2 }')" "codex"
check "plan_executors ignores a fenced Executor line" \
  "$(plan_executors "$TMP/exec.md" | awk -F'\t' '$1 == 3 { print $2 }')" ""
check "plan_executors matches a line in any part" \
  "$(plan_executors "$TMP/exec.md" | awk -F'\t' '$1 == 4 { print $2 }')" "codex"
check "plan_executors emits one row per task" \
  "$(plan_executors "$TMP/exec.md" | wc -l | tr -d ' ')" "2"

# --- plan_delegated gains the executor kind --------------------------------
check "an offloaded task is delegated as executor" \
  "$(plan_delegated "$TMP/exec.md" | awk -F'\t' '$1 == 2 { print $2 }')" "executor"
check "a plain task is not delegated" \
  "$(plan_delegated "$TMP/exec.md" | awk -F'\t' '$1 == 1 { print $2 }')" ""
check "heavy wins over executor on a split task" \
  "$(plan_delegated "$TMP/exec.md" | awk -F'\t' '$1 == 4 { print $2 }')" "heavy"

# --- the four-band threshold counts the original population ----------------
# Six tasks, three at total 4, one of them offloaded. 3 x 3 > 6, so no
# four-band task delegates. If the offloaded one left the numerator, 3 x 2 <= 6
# would newly delegate the other two - tasks nobody marked for offload.
{ printf '# Threshold Fixture\n\n'
  for i in 1 2 3; do
    printf '### Task %s: four band\n\n**Implementer:** dr-superpowers:impl-opus-low\n' "$i"
    [ "$i" = 1 ] && printf '**Executor:** codex gpt-5.6-sol / high\n'
    printf '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4\n\n'
  done
  for i in 4 5 6; do
    printf '### Task %s: small\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n' "$i"
  done
} > "$TMP/threshold.md"

check "the offloaded four-band task delegates as executor" \
  "$(plan_delegated "$TMP/threshold.md" | awk -F'\t' '$1 == 1 { print $2 }')" "executor"
check "the other four-band tasks stay in session" \
  "$(plan_delegated "$TMP/threshold.md" | awk -F'\t' '$1 == 2 || $1 == 3 { print $2 }' | tr '\n' ',')" ""
check "the delegated set is the offloaded task alone" \
  "$(plan_delegated "$TMP/threshold.md" | wc -l | tr -d ' ')" "1"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/plan-lib.test.sh 2>&1 | grep -c '^FAIL'`
Expected: a non-zero count — `plan_executors` is not defined.

- [ ] **Step 3: Add plan_executors**

In `plugins/dr-superpowers/scripts/lib/plan.sh`, directly after `plan_scores`,
add:

```bash
# plan_executors FILE — `<task>\t<id>` for every task carrying an Executor
# line outside a fenced block, in any part. One row per task: a split task
# whose parts each name one takes the first.
#
# The Executor line is the decision the plan already made. Nothing here
# re-evaluates a gate, because execution time must not second-guess planning.
plan_executors() {
  local n _title id
  while IFS=$'\t' read -r n _title; do
    [ -n "$n" ] || continue
    id=$(plan_task_text "$1" "$n" | awk "$_PLAN_AWK"'
      in_fence($0) { next }
      /^\*\*Executor:\*\*/ { sub(/^\*\*Executor:\*\*[ \t]*/, ""); print $1; exit }')
    [ -n "$id" ] && printf '%s\t%s\n' "$n" "$id"
  done < <(plan_tasks "$1")
}
```

- [ ] **Step 4: Extend plan_delegated**

Replace `plan_delegated` with:

```bash
plan_delegated() {
  local tasks execs
  tasks=$(plan_tasks "$1" | grep -c . || true)
  execs=$(plan_executors "$1" | cut -f1 | tr '\n' ' ')
  plan_scores "$1" | awk -F'\t' -v n="$tasks" -v execs=" $execs" '
    $2 == "-" || $2 == "?" { next }
    # Heavy first: a heavy task is delegated whatever else it is, and the
    # (heavy) label is what the preflight ruling keys on.
    $2 + 0 >= 5 || $3 + 0 == 3 { row[++k] = $1 "\theavy"; next }
    # A total-4 task counts toward the four-band population whether or not it
    # is offloaded. Removing it from the numerator could flip the threshold
    # and newly delegate other four-band tasks nobody marked.
    $2 + 0 == 4 { four++ }
    index(execs, " " $1 " ") > 0 { row[++k] = $1 "\texecutor"; next }
    $2 + 0 == 4 { row[++k] = $1 "\ttotal 4" }
    END {
      for (i = 1; i <= k; i++)
        if (row[i] !~ /\ttotal 4$/ || 3 * four <= n + 0) print row[i]
    }
  '
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 120 bash tests/plan-lib.test.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 6: Check the dependent suites**

`plan-lint` derives an inline plan's model and effort from `plan_delegated`,
so run it and `inline-mode` now rather than discovering a move later:

```bash
cd plugins/dr-superpowers
timeout 300 bash tests/plan-lint.test.sh  | tail -1
timeout 300 bash tests/inline-mode.test.sh | tail -1
```

Expected: `0 failed` for both. Every existing fixture sits on a subagent-mode
base plan, where the delegated rows are ignored, so nothing moves here. Task 9
adds the inline fixtures that exercise the new verdicts.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/tests/plan-lib.test.sh
git commit -m "feat(superpowers): delegate offloaded tasks in inline plans"
```

---

### Task 8: task-brief renders the executor marker

**Files:**
- Modify: `plugins/dr-superpowers/scripts/task-brief:56-63`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh` (append one block)

**Interfaces:**
- Consumes: the `executor` row kind from `plan_delegated` (Contracts).
- Produces: the `Task <n> (executor)` marker in the Dispatch line (Contracts).


**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

`task-brief` already renders whatever kind `plan_delegated` prints, so the
header needs no change at all. What this task proves is that it does, and it
fixes the one place the brief's second line would otherwise mislead.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/inline-mode.test.sh`, before its
summary:

```bash
# --- the executor marker in the Dispatch line -------------------------------
sed 's/^|//' > "$TMP/offload.md" <<'EOF'
|# Offload Fixture
|
|**Goal:** Fixture.
|
|**Execution:** inline — `claude --model sonnet --effort high` — fixture
|
|## Task index
|
|1. offloaded
|2. plain
|
|### Task 1: offloaded
|
|**Implementer:** dr-superpowers:impl-sonnet-medium
|**Executor:** codex gpt-5.5 / medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 2: plain
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
EOF

hdr=$(timeout 60 bash "$P/scripts/task-brief" "$TMP/offload.md" --header 2>/dev/null)
check "the header marks an offloaded task" \
  "$(grep -c 'Task 1 (executor)' <<<"$hdr")" "1"
check "the header does not mark a plain task" \
  "$(grep -c 'Task 2' <<<"$hdr")" "0"

brief=$(timeout 60 bash "$P/scripts/task-brief" "$TMP/offload.md" 1 2>/dev/null)
check "an offloaded brief is marked delegated" \
  "$(sed -n 2p <<<"$brief")" "**Dispatch:** delegated — total 2, risk 0"
brief2=$(timeout 60 bash "$P/scripts/task-brief" "$TMP/offload.md" 2 2>/dev/null)
check "a self-implemented brief carries no Dispatch line" \
  "$(grep -c '^\*\*Dispatch:\*\*' <<<"$brief2")" "0"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/inline-mode.test.sh 2>&1 | grep '^FAIL' | head -3`
Expected: FAIL on "the header marks an offloaded task" only if Task 7 is not
yet in place. With Task 7 committed, all four pass already — run Step 2 anyway
and record which, because that is the evidence this task is a proof rather
than a change.

- [ ] **Step 3: State the rendering rule in the script**

`task-brief` interpolates the kind, so no logic changes. Make that deliberate
rather than accidental by replacing the comment at `scripts/task-brief:47-48`

```bash
# Mixed mode: an inline plan delegates the tasks plan_delegated names. The
# lines are computed here so an executing session never re-scores a task.
```

with

```bash
# Mixed mode: an inline plan delegates the tasks plan_delegated names - heavy
# tasks, four-band tasks under the threshold, and tasks carrying an Executor
# line. The kind is interpolated, so a new row kind needs no change here. The
# lines are computed here so an executing session never re-scores a task.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/inline-mode.test.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "test(superpowers): pin the executor dispatch marker"
```

---

### Task 9: plan-lint inline fixtures for the offload

**Files:**
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh` (append one block)

**Interfaces:**
- Consumes: `plan_delegated`'s `executor` row kind (Contracts).
- Produces: nothing.


**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

Task 7 changes what `plan-lint` requires of an inline plan's Execution line,
and no existing fixture exercises it: the Executor fixtures all sit on the
subagent-mode base plan, where delegated rows are ignored. These fixtures pin
both consequences so a later change cannot undo them silently.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/plan-lint.test.sh`, before its summary:

```bash
# --- an inline plan that offloads ------------------------------------------
# Two consequences, both intended: an offloaded task leaves self_max, so a
# total-4 offload no longer forces opus; and any delegation raises the
# required effort to high.
inline_plan() { # inline_plan <file> <execution line> <extra sed>
  sed 's/^|//' > "$TMP/$1" <<'EOF'
|# Inline Offload Fixture
|
|**Goal:** Fixture.
|
|**Spec:** docs/superpowers/specs/fixture.md
|
|EXECUTION_LINE
|
|## Global Constraints
|
|None.
|
|## Contracts
|
|None.
|
|## Assumptions (evidence)
|
|- Fixture.
|
|## Task index
|
|1. offloaded four band
|2. small
|
|> **External executors:** codex
|
|### Task 1: offloaded four band
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Executor:** codex gpt-5.6-sol / high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 2: small
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
EOF
  perl -0pi -e "s/EXECUTION_LINE/\Q$2\E/" "$TMP/$1"
  perl -0pi -e 's/\\//g' "$TMP/$1"
}

inline_plan i1.md '**Execution:** inline — `claude --model sonnet --effort high` — fixture'
lint i1.md
lacks "an offloaded total-4 task does not force opus" "$out" "needs --model opus"
has "an offloading inline plan lists its delegated task" "$out" "NOTE header: delegated: Task 1 (executor)"

inline_plan i2.md '**Execution:** inline — `claude --model sonnet --effort low` — fixture'
lint i2.md
has "an offloading inline plan needs high effort" "$out" "ERROR header: inline execution needs --effort high or above (effort low)"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/plan-lint.test.sh 2>&1 | grep '^FAIL' | head -3`
Expected: without Task 7 the offloaded task is a plain four-band task, so
`i1.md` reports `needs --model opus` and the NOTE line is absent. With Task 7
committed the three assertions pass; run this step and record which, because
that record is what proves Task 7's effect reaches `plan-lint`.

- [ ] **Step 3: No implementation**

This task adds no production code. Its deliverable is the pin.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/plan-lint.test.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "test(superpowers): pin inline offload lint verdicts"
```

---

### Task 10: review-route ruling kinds

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route:187`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh` (append one block)

**Interfaces:**
- Consumes: nothing.
- Produces: the `executor-empty-diff` ruling kind and the legacy-spelling rule (Contracts). Task 14 updates the prose that names the kind.


**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

The legacy spelling is accepted and **prints itself**. `review-route:205`
echoes the kind it was given, so canonicalising on output would change an
observable for an existing caller.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/review-route.test.sh`, before its
summary:

```bash
# --- ruling kinds are executor-neutral --------------------------------------
out=$(bash "$ROUTE" "$TMP/plan.md" --ruling executor-empty-diff 1 2>/dev/null); rc=$?
check "the neutral ruling kind is accepted" "$rc" "0"
check "the neutral kind prints itself" \
  "$out" "review-seat ruling=executor-empty-diff tasks=1 primary=dr-superpowers:judge-opus fallback=- reason=routine"

out=$(bash "$ROUTE" "$TMP/plan.md" --ruling codex-empty-diff 1 2>/dev/null); rc=$?
check "the legacy ruling kind is still accepted" "$rc" "0"
check "the legacy kind prints its own spelling, not the new one" \
  "$out" "review-seat ruling=codex-empty-diff tasks=1 primary=dr-superpowers:judge-opus fallback=- reason=routine"

out=$(bash "$ROUTE" "$TMP/plan.md" --ruling executor-empty-diff 8 2>/dev/null)
check "a risk-3 task still routes the neutral kind to Fable" \
  "$out" "review-seat ruling=executor-empty-diff tasks=8 primary=dr-superpowers:judge-fable fallback=- reason=risk"

bash "$ROUTE" "$TMP/plan.md" --ruling nonsense-kind 1 >/dev/null 2>&1
check "an unknown ruling kind is still rejected" "$?" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/review-route.test.sh 2>&1 | grep '^FAIL' | head -3`
Expected: FAIL on "the neutral ruling kind is accepted" — `review-route` dies
with `not a ruling kind: executor-empty-diff`.

- [ ] **Step 3: Accept both spellings**

In `plugins/dr-superpowers/scripts/review-route`, replace the allowlist at 187

```bash
      preflight|plan-conflict|cannot-verify|breaker|blocked-plan|codex-empty-diff|final-residual) ;;
```

with

```bash
      # executor-empty-diff is the neutral kind. codex-empty-diff is its
      # earlier name and stays accepted, but it is not canonicalised: the
      # printf below echoes $kind, so rewriting it here would change an
      # existing caller's output.
      preflight|plan-conflict|cannot-verify|breaker|blocked-plan) ;;
      executor-empty-diff|codex-empty-diff) ;;
      final-residual) ;;
```

Nothing else changes: `$kind` reaches the `printf` untouched, and both
spellings take the same routing, because the routing has never depended on the
kind for these cases.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/review-route.test.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): add the executor-empty-diff ruling kind"
```

---

### Task 11: Ownership release between consecutive offloads

**Files:**
- Modify: `plugins/dr-superpowers/reference/delegated-task.md` (the completion step)
- Test: `plugins/dr-superpowers/tests/executor-recovery.test.sh` (append one block)

**Interfaces:**
- Consumes: `run-codex-task.sh --release`, which exists today.
- Produces: the rule that a completed offloaded task releases its worktree before the next one starts.


**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

`lib/task-state.sh` keeps `owner.json` for a worktree and rejects a different
task id in it. An inline plan that offloads several cheap tasks runs them into
one worktree in sequence, so without an explicit release every offload after
the first fails preflight. This is the most likely way the offload breaks in
practice, and nothing in the loop released ownership before now.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/executor-recovery.test.sh`, before its
summary:

```bash
# --- consecutive offloads in one worktree -----------------------------------
# The offload path runs several tasks into the same worktree. Without a
# release between them the second fails preflight on the first task's owner
# record, which is the failure the loop's new release step prevents.
git -C "$fixture/primary" worktree add -qb consecutive "$fixture/consecutive"

STUB_WRITE_PATH=one.txt run --cwd "$fixture/consecutive" --task-id offload-one
check 'first offloaded task succeeds' "$?" 0

STUB_WRITE_PATH=two.txt run --cwd "$fixture/consecutive" --task-id offload-two
check 'a second task without a release is refused' "$([ $? -eq 0 ] && echo allowed || echo refused)" refused

bash "$SCRIPT" --cwd "$fixture/consecutive" --task-id offload-one --release >/dev/null 2>&1
check 'the first task releases ownership' "$?" 0

STUB_WRITE_PATH=two.txt run --cwd "$fixture/consecutive" --task-id offload-two
check 'a released worktree accepts the next offload' "$?" 0
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/executor-recovery.test.sh 2>&1 | grep '^FAIL' | head -3`
Expected: the four assertions describe behaviour the wrapper already has, so
they pass. What fails today is the process: nothing tells a controller to run
the release. Record the pass and continue — Step 3 is the deliverable.

- [ ] **Step 3: Require the release in the loop**

In `plugins/dr-superpowers/reference/delegated-task.md`, in the section that
writes the task's complete line, add immediately after the complete line is
recorded:

```markdown
**Release the worktree when the task is complete.** A task that reached a
reviewed complete line no longer owns its worktree:

```bash
bash "<plugin-root>/scripts/run-<executor>-task.sh" \
  --cwd <worktree-root> --task-id <stable-task-id> --release
```

`scripts/lib/task-state.sh` keeps an `owner.json` per worktree and refuses a
different task id in it, so an unreleased worktree fails the next offload's
preflight. An inline plan offloads several tasks into one worktree in
sequence, which makes this the ordinary case rather than a recovery step.

**After a `HANDBACK`, reconcile rather than release.** The Claude implementer
inherits the worktree, its commits and its report, so ownership passes to a
task that is still in flight. Follow
[external-task-recovery.md](external-task-recovery.md) §Ownership before the
implementer is dispatched; a bare `--release` there would drop the record the
recovery procedure reads.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/executor-recovery.test.sh | tail -1`
Expected: `49 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/reference/delegated-task.md plugins/dr-superpowers/tests/executor-recovery.test.sh
git commit -m "docs(superpowers): release the worktree between offloads"
```

---

### Task 12: Remove the unreachable survivor path

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-task.sh:106-109` (the stale comment), `:275`, `:360-361`, `:364` (the survivor statements)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. Task 13's reference rewrite documents what replaces the note.


**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

`survivor=yes` is never assigned anywhere in the file, so
`note=codex-may-still-be-running` cannot print and a controller is told to
handle a state it can never observe. `tests/run-codex-task.test.sh` asserts
nothing on `note=` or the survivor path, so this task must leave that suite
untouched.

- [ ] **Step 1: Confirm the path is dead**

```bash
cd plugins/dr-superpowers
grep -c 'survivor=yes' scripts/run-codex-task.sh
grep -c 'survivor\|codex-may-still-be-running' tests/run-codex-task.test.sh
```

Expected: `0` and `0`. If either is non-zero, stop: the premise is wrong and
this task needs re-designing rather than executing.

- [ ] **Step 2: Correct the stale comment**

Replace lines 106-109:

```bash
# Whole seconds only. `[ "$waited" -lt "$timeout_s" ]` errors and evaluates
# false on a value like "30m", so the poll loop never runs, the tree is killed
# about a second after launch, and the run is reported as BLOCKED - the exact
# opposite of what raising the timeout was meant to do.
```

with:

```bash
# Whole seconds only. The value becomes the client's deadline and the outer
# coreutils bound below; a value like "30m" makes the arithmetic below fail
# and the run is reported as BLOCKED - the exact opposite of what raising the
# timeout was meant to do.
```

- [ ] **Step 3: Remove the survivor statements**

Delete line 275:

```bash
survivor=no
```

Replace lines 360-364:

```bash
# Notes accumulate rather than replace one another: a run can both time out and
# leave a survivor, and the old single-slot note reported only the second.
notes=""
[ "$timed_out" = yes ] && notes="$notes note=timed-out"
[ "$survivor" = yes ] && notes="$notes note=codex-may-still-be-running"
```

with:

```bash
# Notes accumulate rather than replace one another, so a run that earns two
# reports both.
notes=""
[ "$timed_out" = yes ] && notes="$notes note=timed-out"
```

- [ ] **Step 4: Prove the variable is gone**

Run: `cd plugins/dr-superpowers && grep -c survivor scripts/run-codex-task.sh`
Expected: `0`.

- [ ] **Step 5: Run the affected suites**

```bash
cd plugins/dr-superpowers
timeout 300 bash tests/run-codex-task.test.sh | tail -1
timeout 300 bash tests/executor-recovery.test.sh | tail -1
```

Expected: `0 failed` for both, with no assertion changed in either.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-task.sh
git commit -m "fix(superpowers): drop the unreachable survivor note"
```

---

### Task 13: The executor-neutral reference

**Files:**
- Rename: `plugins/dr-superpowers/reference/external-executor.md` to `plugins/dr-superpowers/reference/executor-lane.md`
- Modify: the renamed file, per the substitutions below
- Test: `plugins/dr-superpowers/tests/review-route.test.sh` (append one block)

**Interfaces:**
- Consumes: the `scripts/executors` CLI (Contracts), which the neutral prose tells a controller to resolve fields through.
- Produces: `reference/executor-lane.md` (Contracts). Task 14 repoints every referrer.


**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

The document keeps its structure, its failure taxonomy and its rules. What
changes is that the executor is a parameter: the controller resolves the gate,
the wrapper, the reference and the successor block through `scripts/executors`
rather than naming Codex. Codex keeps a section of its own for what is
genuinely Codex-specific.

The three code/document mismatches this file carried were corrected in
`a74f8e8` before this plan began, so the rename inherits a correct document.
Do not reintroduce them.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/review-route.test.sh`, before its
summary:

```bash
# --- the executor lane reference -------------------------------------------
LANE="$P/reference/executor-lane.md"
check "the neutral reference exists" "$([ -f "$LANE" ] && echo yes || echo no)" "yes"
check "the Codex-only reference is gone" \
  "$([ -f "$P/reference/external-executor.md" ] && echo present || echo gone)" "gone"
present "the reference resolves the gate through the registry" "$LANE" 'executors get <id> gate'
present "the reference resolves the wrapper through the registry" "$LANE" 'executors path <id> wrapper'
present "the reference keeps a per-executor section" "$LANE" '## Per-executor: codex'
present "the reference names the neutral ruling kind" "$LANE" 'executor-empty-diff'
present "the reference keeps the background-call rule" "$LANE" 'background Bash call'
present "the reference keeps the two-failure budget" "$LANE" 'two'
present "the reference documents the wedged-client case" "$LANE" 'reaped'
absent "the reference no longer claims a wrapper poll loop" "$LANE" "wrapper's own poll loop"
absent "the reference no longer names the unreachable survivor note" "$LANE" 'codex-may-still-be-running'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/review-route.test.sh 2>&1 | grep '^FAIL' | head -3`
Expected: FAIL on "the neutral reference exists".

- [ ] **Step 3: Rename the file**

```bash
git mv plugins/dr-superpowers/reference/external-executor.md \
       plugins/dr-superpowers/reference/executor-lane.md
```

- [ ] **Step 4: Neutralise the prose**

Apply these substitutions throughout `reference/executor-lane.md`. Each is a
literal replacement; `<id>` and `<executor>` are placeholders the controller
fills from the plan's `**Executor:**` line, and every one of them is stated as
such in the opening paragraph added below.

| Replace | With |
|---|---|
| `# External executor lane` | `# External executor lane` (unchanged) |
| `This reference holds the Claude-hosted Codex CLI lane.` | `This reference holds the Claude-hosted external executor lanes. Everything below is written for an executor id `<id>`, which the task's `**Executor:**` line names as its first token. Resolve that executor's scripts and policy through `scripts/executors`: its gate is `bash "$(executors path <id> gate)"`, its wrapper `bash "$(executors path <id> wrapper)"`, and its ladder blocks are named by `executors get <id> blocks.assignment`, `blocks.successor` and `blocks.timeout`. Where an executor needs something this file cannot say generically, its own section at the foot of this file says it.` |
| `bash "<plugin-root>/scripts/codex-gate"` (every occurrence) | `bash "$(bash "<plugin-root>/scripts/executors" path <id> gate)"` |
| `bash "<plugin-root>/scripts/run-codex-task.sh"` (every occurrence) | `bash "$(bash "<plugin-root>/scripts/executors" path <id> wrapper)"` |
| `the `codex-assignment` block` | `that executor's assignment block (`executors get <id> blocks.assignment`)` |
| `the `codex-successor` block` | `that executor's successor block (`executors get <id> blocks.successor`)` |
| `` `codex-timeout` `` (as a block name) | `` that executor's timeout block `` |
| `codex off — <reason>` | `<id> off — <reason>` |
| `an executor was ticked` | `the executor named on the line was ticked` |
| `> **External executors:** codex` | `> **External executors:** <id>` |
| `**Executor:** codex gpt-5.5 / medium` | `**Executor:** <id> <model> / <effort>` |
| `executor codex gpt-5.5/medium, thread 01a0...` | `executor <id> <model>/<effort>, thread 01a0...` |
| `executor codex unavailable - <reason>` | `executor <id> unavailable - <reason>` |
| `a `codex-empty-diff` item` | `an `executor-empty-diff` item` |
| `## Codex error` (as the report heading) | `## Executor error` |
| `Read `## Codex error` in the report` | `Read `## Executor error` in the report` |
| `A native Codex host never uses this lane` | `A native Codex host never uses these lanes` |

Leave every rule, threshold and table row exactly as it is: the two-failure
budget, the round-4 handback, the five-round cap, the retry-once rules, the
exit-code table, the review-seat routing and the final-review round all apply
unchanged. Only the names become parameters.

- [ ] **Step 5: Add the per-executor section**

Append to `reference/executor-lane.md`:

```markdown
## Per-executor: codex

Everything above applies to Codex with `<id>` read as `codex`. What is
specific to it:

- **Review seats.** Codex is the only executor with a `review` surface, so the
  seats described above — `codex:light`, `codex:heavy`,
  `codex:heavy+judge-fable` — and the final-review round are Codex's alone.
  `scripts/run-codex-review.sh` is not registry-aware and takes its model from
  the `codex-judge` block directly. An executor whose registry entry does not
  list `review` in `surfaces` staffs no seat.
- **The locator and the gate.** Codex is reached only through the official
  `codex@openai-codex` plugin, which owns the binary. `scripts/codex-plugin`
  locates it and `scripts/codex-gate` reads login and quota through the
  plugin's own client. Another executor's gate answers whatever question its
  own authentication poses.
- **Quota.** Codex reports a reset time, which the gate caches, so a quota
  answer is re-probed once that time has passed. An executor whose provider
  publishes no reset time marks itself off for the session instead.
- **Effort values.** `low`, `medium`, `high`, `xhigh` and `ultra`; `minimal`
  is rejected. Another executor's efforts are whatever its assignment block
  names, and its wrapper validates them.

## When the client itself wedges

The wrapper bounds its client with `timeout $((timeout_s + 60))`, which fires
only when the client fails to honour its own deadline. That run reports
`exit=1 status=BLOCKED` with no error section, and on Windows a grandchild may
outlive it.

Read the durable task record's `phase` and `reaped` as **evidence, not proof**.
`reaped: false` can mean the client correctly left a pre-existing broker alone
rather than that a process survived, and a reap can report success while
teardown failed. Where the evidence is inconclusive — `reaped: false` with no
recorded pre-existing broker, or a client that never answered — reconcile
process ownership before retrying, resuming or handing back. A retry into an
unreconciled worktree puts two runs in one tree, which is the hazard the old
`note=codex-may-still-be-running` row gestured at without ever being able to
fire.
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/review-route.test.sh | tail -1`
Expected: `0 failed`. The suite's existing `external-executor.md` path
assertions move in Task 14; if any fails here, note it and fix it there rather
than editing an assertion now.

- [ ] **Step 7: Commit**

```bash
git add -A plugins/dr-superpowers/reference plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "docs(superpowers): make the lane reference executor-neutral"
```

---

### Task 14: Repoint every reference link

**Files:**
- Modify: `plugins/dr-superpowers/README.md`
- Modify: `plugins/dr-superpowers/reference/delegated-task.md` (lines 27, 50, 111, 196, 278)
- Modify: `plugins/dr-superpowers/reference/final-review.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/escalation.md`
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: `reference/executor-lane.md` (Contracts).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

One decision repeated across eight files: the reference changed name. Nothing
else in this task changes.

- [ ] **Step 1: List the referrers**

```bash
cd plugins/dr-superpowers
grep -rln 'external-executor' . --exclude-dir=.git
```

Expected: `README.md`, `reference/delegated-task.md`,
`reference/final-review.md`,
`skills/subagent-driven-development/references/escalation.md`,
`skills/subagent-driven-development/SKILL.md`, `skills/writing-plans/SKILL.md`,
`tests/inline-mode.test.sh`, `tests/review-route.test.sh`.

- [ ] **Step 2: Repoint them**

```bash
cd plugins/dr-superpowers
grep -rl 'external-executor' . --exclude-dir=.git \
  | xargs sed -i 's/external-executor\.md/executor-lane.md/g; s/external-executor/executor-lane/g'
```

- [ ] **Step 3: Verify nothing references the old name**

Run: `cd plugins/dr-superpowers && grep -rn 'external-executor' . --exclude-dir=.git`
Expected: no output.

- [ ] **Step 4: Run the suites**

```bash
cd plugins/dr-superpowers
timeout 300 bash tests/inline-mode.test.sh  | tail -1
timeout 300 bash tests/review-route.test.sh | tail -1
```

Expected: `0 failed` for both. The path assertions inside those suites were
rewritten by Step 2 along with everything else, which is correct: they pin the
path, and the path moved.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dr-superpowers
git commit -m "docs(superpowers): repoint the lane reference links"
```

---

### Task 15: The delegated-set definitions

**Files:**
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` (lines 50-55, 164)
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md` (line 265)
- Modify: `plugins/dr-superpowers/reference/delegated-task.md` (lines 5-9)
- Modify: `plugins/dr-superpowers/README.md` (the sentence naming the delegation reasons)
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh` (move three pins)

**Interfaces:**
- Consumes: the `executor` row kind (Contracts).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

These four sentences are the definition of the delegated set, and
`tests/inline-mode.test.sh:101,105-106` pin three of them verbatim. This is the
one task in the plan where changing an existing assertion is correct rather
than a defect signal, because the sentence it quotes is what changed.

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, replace the pin at line
101 and the two at 105-106 with:

```bash
present "inline mode names all three delegation reasons" "$INLINE" 'Task <c> (executor)'
present "README names all three reasons for delegation" "$P/README.md" 'every task carrying an'
present "the delegated loop names all three reasons" "$P/reference/delegated-task.md" 'every task carrying an'
absent "inline mode no longer calls executor lines inert" "$INLINE" 'lines are inert for the tasks you'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/inline-mode.test.sh 2>&1 | grep -c '^FAIL'`
Expected: `4`.

- [ ] **Step 3: Extend the definition in executing-plans**

Replace lines 50-55 of `skills/executing-plans/SKILL.md`, which currently read:

```markdown
**Delegated tasks.** A delegated task is not yours to implement: every heavy
task, and each total-4 task while those are a third of the plan or fewer, so it
gets an independent review without putting the whole session on Opus. Its
brief's second line is `**Dispatch:** delegated — total <t>, risk <r>`, and
`plan-header.md` ends with
`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4)`.
```

with:

```markdown
**Delegated tasks.** A delegated task is not yours to implement: every heavy
task, each total-4 task while those are a third of the plan or fewer, and
every task carrying an `**Executor:**` line, so it gets an independent review
without putting the whole session on Opus. An offloaded task is delegated for
the same reason the others are — the session does not implement it — and it
runs on its executor's wrapper rather than an implementer subagent. Its
brief's second line is `**Dispatch:** delegated — total <t>, risk <r>`, and
`plan-header.md` ends with
`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4), Task <c> (executor)`.
```

- [ ] **Step 4: Replace the inert rule, both copies**

In `skills/executing-plans/SKILL.md` at line 164, replace:

```markdown
`**Executor:**` lines are inert for the tasks you
implement; a delegated task's is read by
[delegated-task.md](../../reference/delegated-task.md) §1.
```

with:

```markdown
A task whose brief's second line marks it delegated is dispatched, never
implemented here, and its `**Executor:**` line is read by
[delegated-task.md](../../reference/delegated-task.md) §1, which runs that
executor's wrapper in place of an implementer subagent.
```

Replace the second copy at `skills/writing-plans/SKILL.md:265` with the same
two sentences.

- [ ] **Step 5: Extend the other two definitions**

In `reference/delegated-task.md` lines 5-9 and in the `README.md` sentence
naming the delegation reasons, add the same third reason, using the exact
phrase "every task carrying an" so the pins in Step 1 match.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/inline-mode.test.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add -A plugins/dr-superpowers
git commit -m "docs(superpowers): delegate offloaded tasks in the prose"
```

---

### Task 16: The ruling kind and the ledger grammar

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (the ruling table, the ledger grammar)
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/ruling-prompt.md:96`
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md:346-347` and its kinds table
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/escalation.md` (the Codex-session sentence)
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: the `executor-empty-diff` ruling kind (Contracts).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/inline-mode.test.sh`, before its
summary:

```bash
present "inline mode routes the executor empty-diff kind" "$INLINE" 'executor-empty-diff'
absent "inline mode no longer says it never runs an external executor" "$INLINE" 'no external executor'
```

Append to `plugins/dr-superpowers/tests/review-route.test.sh`, before its
summary:

```bash
RP="$P/skills/subagent-driven-development/references/ruling-prompt.md"
present "the ruling prompt explains the neutral kind" "$RP" 'executor-empty-diff'
absent "the ruling prompt no longer names the Codex-only kind" "$RP" 'codex-empty-diff'
present "the ledger grammar is executor-neutral" "$SDD" 'executor <id> <model>/<effort>, thread'
```

`$SDD` is already defined in that suite's plan-review prose block.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/review-route.test.sh 2>&1 | grep -c '^FAIL'`
Expected: a non-zero count.

- [ ] **Step 3: Rename the kind in the prompt**

In `skills/subagent-driven-development/references/ruling-prompt.md:96`, replace
`codex-empty-diff` with `executor-empty-diff`, and rewrite its explanation so
it names the executor generically: an executor's fix round returned DONE with
an empty diff, arguing the findings are already addressed or wrong, and the
seat rules on that argument.

- [ ] **Step 4: Rename it in the seats table and fix the ledger grammar**

In `skills/subagent-driven-development/SKILL.md`, change `codex-empty-diff` to
`executor-empty-diff` in the ruling table, and change the ledger grammar from
`executor codex <m>/<e>, thread <id>` to
`executor <id> <model>/<effort>, thread <id>`. The field name `thread` does not
change: `lib/task-state.sh` stores `thread` and the wrapper prints `thread=`.

- [ ] **Step 5: Make the kind reachable in inline mode**

In `skills/executing-plans/SKILL.md` at lines 346-347, replace:

```markdown
Only `codex-empty-diff` belongs to a seat this mode never runs (no external
executor)
```

with:

```markdown
`executor-empty-diff` is reachable here too: an inline plan dispatches its
offloaded tasks, so one of their fix rounds can return DONE with an empty diff
```

and add `executor-empty-diff` to that section's kinds table with the same
description the subagent skill gives it.

- [ ] **Step 6: Generalise the escalation sentence**

In `skills/subagent-driven-development/references/escalation.md`, replace the
statement that an external task resumes a Codex session with one naming the
executor's own session, resolved from the task's `**Executor:**` line.

- [ ] **Step 7: Run the suites**

```bash
cd plugins/dr-superpowers
timeout 300 bash tests/inline-mode.test.sh  | tail -1
timeout 300 bash tests/review-route.test.sh | tail -1
```

Expected: `0 failed` for both.

- [ ] **Step 8: Commit**

```bash
git add -A plugins/dr-superpowers
git commit -m "docs(superpowers): name the executor-neutral ruling kind"
```

---

### Task 17: Generalise the recovery guide

**Files:**
- Modify: `plugins/dr-superpowers/reference/external-task-recovery.md`
- Test: `plugins/dr-superpowers/tests/executor-recovery.test.sh` (append two prose checks)

**Interfaces:**
- Consumes: the `scripts/executors` CLI (Contracts).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

The recovery contract is already executor-neutral in substance — ownership,
approved write sets, snapshot validation and commit recovery say nothing about
which CLI produced the diff. Only its preamble and its commands name Codex.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/executor-recovery.test.sh`, before its
summary. The suite has no `present`/`absent` helpers, so add them with the
block:

```bash
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'ok - %s\n' "$1"; pass=$((pass+1))
  else printf 'FAIL - %s: missing [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail+1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'FAIL - %s: unexpected [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail+1))
  else printf 'ok - %s\n' "$1"; pass=$((pass+1)); fi
}
REC="$(cd "$(dirname "$SCRIPT")/.." && pwd)/reference/external-task-recovery.md"
present "the recovery guide resolves the wrapper through the registry" "$REC" 'path <id> wrapper'
absent "the recovery guide no longer hardcodes the Codex wrapper" "$REC" 'run-codex-task.sh'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/executor-recovery.test.sh 2>&1 | grep -c '^FAIL'`
Expected: `2`.

- [ ] **Step 3: Replace the preamble**

Replace the guide's opening statement that it covers Codex tasks with one
naming any external executor: the guide applies to a task dispatched to any
executor, `<id>` is the first token of that task's `**Executor:**` line, and
its wrapper is resolved with `scripts/executors path <id> wrapper`.

- [ ] **Step 4: Parameterise the commands**

Replace every literal `scripts/run-codex-task.sh` in the guide's recovery
commands with the resolved wrapper. Every flag — `--release`,
`--recover-commit`, `--handback`, `--amend-write-set`, `--accept-baseline`,
`--approval` — is unchanged, because they belong to the shared task-state
library rather than to Codex.

```bash
cd plugins/dr-superpowers
grep -c 'run-codex-task' reference/external-task-recovery.md
```

Expected after the edit: `0`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/executor-recovery.test.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/external-task-recovery.md plugins/dr-superpowers/tests/executor-recovery.test.sh
git commit -m "docs(superpowers): generalise the recovery guide"
```

---

### Task 18: Version bump and release

**Files:**
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh` (the two pinned version assertions)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, change the two version
assertions from `1.15.1` to `1.16.0`:

```bash
present "the Claude manifest is 1.16.0" "$P/.claude-plugin/plugin.json" '"version": "1.16.0"'
present "the Codex manifest is 1.16.0" "$P/.codex-plugin/plugin.json" '"version": "1.16.0"'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/review-route.test.sh 2>&1 | grep -c '^FAIL'`
Expected: `2`.

- [ ] **Step 3: Bump both manifests**

```bash
cd D:/Repositories/Personal/darkraise-ai-plugins
sed -i 's/"version": "1.15.1"/"version": "1.16.0"/' \
  plugins/dr-superpowers/.claude-plugin/plugin.json \
  plugins/dr-superpowers/.codex-plugin/plugin.json
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd plugins/dr-superpowers && timeout 300 bash tests/review-route.test.sh | tail -1`
Expected: `0 failed`.

- [ ] **Step 5: Validate the repository**

```bash
cd D:/Repositories/Personal/darkraise-ai-plugins
timeout 120 node scripts/validate-repository.mjs
timeout 600 node scripts/test-all.mjs 2>&1 | tail -20
```

Expected: `Repository catalogs, manifests, versions, and bundled links are valid.`
and a test summary whose only failure is the pre-existing
`tests/ui-discovery.test.mjs` case that needs `rg` on PATH. Any other failure
is a defect from this plan.

- [ ] **Step 6: Validate the plugins**

```bash
cd D:/Repositories/Personal/darkraise-ai-plugins
timeout 120 claude plugin validate .claude-plugin/marketplace.json
timeout 120 claude plugin validate plugins/dr-superpowers
```

Expected: both report valid. Terminate any process these commands leave
running before completing the task.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): release 1.16.0"
```
