# Item Registers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give dr-superpowers a first-class item register, so no surface can claim a body of work complete while a source item is unresolved.

**Architecture:** A register is a committed markdown table under `docs/superpowers/registers/`, parsed by a new `scripts/lib/register.sh` that reuses `lib/plan.sh`'s CommonMark fence rule, and written only through a new `scripts/register`. Readers resolve a register from a plan's `**Spec:**` and `**Program:**` spec paths rather than from a pointer inside the plan, so the link cannot go stale. `next-step`, `plan-lint`, `repo-audit` and three skills consult it; when no register covers a spec, every surface behaves exactly as it does today.

**Tech Stack:** Bash 5 with `set -uo pipefail`, POSIX awk, git; the Node test runner `scripts/test-all.mjs` discovers `plugins/dr-superpowers/tests/*.test.sh` automatically.

**Spec:** docs/superpowers/specs/2026-09-20-dr-superpowers-item-registers-design.md

**Execution:** inline — `claude --model sonnet --effort high` — one heavy task (Task 5, total 5) is delegated; every other task is sonnet-band.

**Plan review:** 2026-09-20 — dr-superpowers:judge-opus — executability 16 / coherence 17 / coverage 17 / assumptions 16 (round 2)

## Global Constraints

- Call every plugin script as `bash plugins/dr-superpowers/scripts/<name>` with the working directory inside the repository worktree.
- English only: code, comments, docs, commits, tests.
- Commits are `<type>(<scope>): <subject>`, subject 50 characters or fewer, imperative, no trailing period.
- Comments explain WHY only. Never explain what the code does, and never reference this plan, its tasks or the fix.
- Shell scripts start `set -uo pipefail`; sourced libraries define functions only and never exit.
- Every reader tolerates CRLF by piping through `tr -d '\r'`.
- Library functions must end with `return 0` on their empty path: `scripts/next-step` runs under `set -euo pipefail`, where a function returning non-zero inside a command substitution kills the script.
- The register state vocabulary is exactly `open planned doing verify done deferred n/a`. Unresolved is `open planned doing verify`. A note is mandatory for `verify`, `deferred` and `n/a`.
- Both manifests keep equal versions: `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`.
- Never edit the `darkraise-modder` repository. Never touch or commit `plugins/darkmem-resume/`.

## Contracts

**Register file** — `docs/superpowers/registers/YYYY-MM-DD-<slug>.md`. Header lines `**Source:** <phrase>` and `**Covers:** <comma-separated repository-relative spec paths, or ->`. Table columns, in order: `| # | Item | Assigned | Acceptance | State | Note |`. A literal pipe inside a cell is written `\|`.

**`scripts/lib/register.sh`** — sourced; sources `plan.sh`; defines:

- `REGISTER_STATES` = `open planned doing verify done deferred n/a`
- `REGISTER_UNRESOLVED` = `open planned doing verify`
- `REGISTER_NOTE_REQUIRED` = `verify deferred n/a`
- `_REGISTER_AWK` — awk source defining `reg_cells(line, f)`, which returns the field count from splitting a table line on unescaped pipes and fills `f`
- `register_field FILE LABEL` → the first `**LABEL:**` value outside fences
- `register_scan FILE` → `lineno<TAB>fieldcount<TAB>id<TAB>item<TAB>assigned<TAB>acceptance<TAB>state<TAB>note` for every candidate row line outside fences, header and separator rows excluded
- `register_rows FILE` → `id<TAB>item<TAB>assigned<TAB>acceptance<TAB>state<TAB>note` for well-formed rows only
- `register_open FILE` → the same, filtered to `REGISTER_UNRESOLVED`
- `register_covers FILE` → one repository-relative spec path per line; nothing when `**Covers:**` is `-`
- `register_files ROOT` → every `$ROOT/docs/superpowers/registers/*.md`
- `register_for_spec ROOT SPEC...` → the register files covering any given spec

**`scripts/register`** — `check FILE` (exit 0 clean, 1 errors, 2 usage or missing file); `open [--root DIR] (--spec SPEC | FILE)` (exit 0 nothing open, 1 rows open, 2 usage); `set FILE ID STATE [--note|--assigned|--acceptance TEXT]` (exit 0 written, 2 usage, unknown id, unknown state, missing mandatory note); `add FILE "ITEM" [--assigned|--acceptance|--state|--note TEXT]` (exit 0 written, 2 usage or missing mandatory note).

Internal helpers in that same file, defined once by Task 2 and used by Tasks 3 and 4: `state_known STATE` returns 0 when the state is in `REGISTER_STATES`; `note_required STATE` returns 0 when the state is in `REGISTER_NOTE_REQUIRED`; `blank_note NOTE` returns 0 when the note is empty or `-`; `need_file FILE` exits 2 when the file does not exist.

**Plan task line** — `**Items:** 4, 16`, optional, one per task, citing register identifiers.

**`scripts/next-step` completion output**, when a covering register has unresolved rows:
`**Next:** Register rows still open (<n>) in \`<rel>\`[, \`<rel>\`…]: #<id> <item>; … [+<N> more]. <action>` where `<n>` counts the rows of every covering register, the paths are every covering register that has open rows, and `<action>` is `` `<assigned>`: write its spec in a fresh session. `` or `Rule on the open rows with dr-superpowers:brainstorming.`

**`scripts/repo-audit` section heading** — `## Item registers`.

**First register** — `docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md`, covering `docs/superpowers/specs/2026-09-17-dr-superpowers-review-fixes-design.md`.

## Assumptions (evidence)

- The Codex executor lane is shut: `bash plugins/dr-superpowers/scripts/codex-gate` on 2026-09-20 printed `usable=false reason=quota review=false lane=false source=probe`, so no task carries an `**Executor:**` line.
- `scripts/test-all.mjs:38` discovers `plugins/dr-superpowers/tests/*.test.sh` by directory read, so `tests/register.test.sh` needs no registration.
- `.superpowers/` is git-ignored (`.gitignore:15`), which is why registers live under `docs/` and why Task 12 does not put one in the handoff directory.
- `scripts/lib/plan.sh:12-33` defines `_PLAN_AWK` with `in_fence`; the register library reuses it rather than restating the fence rule.
- `scripts/next-step:173-195` is the completion branch that prints "Nothing — every sub-project … is done"; Task 5 replaces its chain.
- `scripts/plan-lint:69-76` parses the Program line and leaves `ppath`, `k` and `n` set; Task 6 reads `ppath` from there.
- Spec §5.1 lists six library functions. Task 1 adds a seventh, `register_scan`, because `check` needs line numbers and the fence rule belongs in the library rather than duplicated in the script.
- `node scripts/test-all.mjs` exits 1 on this machine for one pre-existing unrelated failure: `tests/ui-discovery.test.mjs` "documented Win32 discovery finds centrally managed versions" fails with `bash: rg: command not found`. Any other failure is this plan's.
- The review-fixes deferral rows in Task 12 are left unassigned (`-`), so `plan-lint` check 1 never fires against the already-merged plan `docs/superpowers/plans/2026-09-17-dr-superpowers-review-fixes.md`.
- `scripts/lib/plan.sh:169-180` defines `plan_repo_canon`, which is how a path is made comparable to `git rev-parse --show-toplevel` output: under Git Bash `pwd` prints `/d/…` where git prints `D:/…`, so Task 6 canonicalises rather than stripping a `pwd` prefix.
- `tests/review-route.test.sh:560-561` pins both manifest versions, so Task 12 updates that suite in the same commit as the bump; verified by reading the file on 2026-09-20.
- Deviation from spec §11: every suite builds its fixtures inline with heredocs rather than under `tests/fixtures/`, matching how `tests/next-step.test.sh`, `tests/plan-lint.test.sh` and `tests/repo-audit.test.sh` already work. No file is added to `tests/fixtures/`.
- Every asserted prose phrase in Tasks 8 to 11 is written on one source line in the markdown those tasks supply, because the suites assert with `grep -F` and a wrapped phrase can never match.
- Deviation from spec §6.1: the completion line reads `Register rows still open (<n>) in \`<rel>\`…` rather than the spec's `Register \`<file>\` has <n> open rows`. Spec §4 unions the rows of every covering register, so naming one file would attribute another register's rows to it. The Contracts entry is the authority.
- The assertion counts in Tasks 1 to 4 were counted from the blocks those steps write on 2026-09-20: 16, 14, 9 and 22, cumulative 16, 30, 39 and 61.

## Task index

1. Register parsing library
2. `register check`
3. `register open` and spec resolution
4. `register set` and `register add`
5. Register-aware completion in `next-step`
6. Register coverage in `plan-lint`
7. Item registers in `repo-audit`
8. Registers in `project-status`
9. Resolving rows in `finishing-a-development-branch`
10. Opening registers in `brainstorming` and `writing-plans`
11. Marking rows `doing`, and the documentation
12. First register and the 1.15.0 release

---

### Task 1: Register parsing library

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/register.sh`
- Create: `plugins/dr-superpowers/tests/register.test.sh`

**Interfaces:**
- Consumes: `_PLAN_AWK` and its `in_fence` from `scripts/lib/plan.sh`.
- Produces: every name in Contracts under `scripts/lib/register.sh`. Tasks 2, 3, 4, 5, 6 and 7 all source this file.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/register.test.sh`:

```bash
#!/usr/bin/env bash
# lib/register.sh is the one register parser every script shares, so all of
# them agree on what a row is: fences by the CommonMark rule, escaped pipes
# inside cells, CRLF tolerated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/register.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

reg() { # reg <file> <rows...>
  local f=$1; shift
  {
    printf '# Sample — item register\n\n'
    printf '**Source:** owner list 2026-09-20\n'
    printf '**Covers:** docs/superpowers/specs/a-design.md, docs/superpowers/specs/b-design.md\n\n'
    printf '| # | Item | Assigned | Acceptance | State | Note |\n'
    printf '|---|---|---|---|---|---|\n'
    printf '%s\n' "$@"
  } > "$f"
}

reg "$TMP/r.md" \
  '| 1 | Tabs in Settings | C2 Settings | Radius follows the axis | planned | - |' \
  '| 2 | Zoom indicator | - | - | done | - |' \
  '| 3 | Stale note | - | - | deferred | out of this batch |'

check "register_field: Source" "$(register_field "$TMP/r.md" Source)" "owner list 2026-09-20"
check "register_rows: identifiers" "$(register_rows "$TMP/r.md" | cut -f1 | tr '\n' ' ')" "1 2 3 "
check "register_rows: states" "$(register_rows "$TMP/r.md" | cut -f5 | tr '\n' '|')" "planned|done|deferred|"
check "register_open: unresolved only" "$(register_open "$TMP/r.md" | cut -f1 | tr '\n' ' ')" "1 "
check "register_covers: two paths" "$(register_covers "$TMP/r.md" | tr '\n' ' ')" \
  "docs/superpowers/specs/a-design.md docs/superpowers/specs/b-design.md "

# The header and separator rows are not items.
check "register_rows: header excluded" "$(register_rows "$TMP/r.md" | grep -c . )" "3"

# A cell may hold an escaped pipe; splitting must not see it.
reg "$TMP/pipe.md" '| 1 | Show a \| b | - | - | open | - |'
check "register_rows: escaped pipe stays in the cell" "$(register_rows "$TMP/pipe.md" | cut -f2)" 'Show a | b'

# Fenced table rows are documentation, not items.
{
  printf '# F — item register\n\n**Source:** s\n**Covers:** -\n\n'
  printf '| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n'
  printf '| 1 | Real | - | - | open | - |\n\n'
  printf '````\n| 9 | Example | - | - | open | - |\n````\n'
} > "$TMP/fenced.md"
check "register_rows: fenced rows ignored" "$(register_rows "$TMP/fenced.md" | cut -f1 | tr '\n' ' ')" "1 "
check "register_covers: a dash covers nothing" "$(register_covers "$TMP/fenced.md")" ""

sed 's/$/\r/' "$TMP/r.md" > "$TMP/crlf.md"
check "register_rows: CRLF" "$(register_rows "$TMP/crlf.md" | cut -f1 | tr '\n' ' ')" "1 2 3 "

# register_scan reports the line number and the field count, which is how
# check tells a short row from a well-formed one.
reg "$TMP/short.md" '| 1 | Missing cells | open |'
check "register_scan: field count of a short row" "$(register_scan "$TMP/short.md" | cut -f2)" "5"
check "register_rows: a short row is not a row" "$(register_rows "$TMP/short.md")" ""

# --- discovery ---
# A real git repository, because `register check` resolves the root with
# git rev-parse and would otherwise fall back to the working directory and
# look for these specs in the checkout running the suite.
ROOT="$TMP/repo"
git init -q -b main "$ROOT"
mkdir -p "$ROOT/docs/superpowers/registers" "$ROOT/docs/superpowers/specs"
: > "$ROOT/docs/superpowers/specs/a-design.md"
: > "$ROOT/docs/superpowers/specs/b-design.md"
reg "$ROOT/docs/superpowers/registers/one.md" '| 1 | A | - | - | open | - |'
printf '# Two — item register\n\n**Source:** s\n**Covers:** docs/superpowers/specs/z-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | B | - | - | open | - |\n' \
  > "$ROOT/docs/superpowers/registers/two.md"
check "register_files: both" "$(register_files "$ROOT" | wc -l | tr -d ' ')" "2"
check "register_for_spec: matches one" \
  "$(register_for_spec "$ROOT" docs/superpowers/specs/a-design.md | xargs -n1 basename | tr '\n' ' ')" "one.md "
check "register_for_spec: no spec argument prints nothing" "$(register_for_spec "$ROOT")" ""
check "register_files: no directory prints nothing" "$(register_files "$TMP/absent")" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/register.test.sh`
Expected: FAIL — `scripts/lib/register.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `plugins/dr-superpowers/scripts/lib/register.sh`:

```bash
# Item register parsing shared by register, next-step, plan-lint and repo-audit,
# so every reader agrees on what a row is. Sourced; defines functions only.

_REGISTER_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_REGISTER_LIB_DIR/plan.sh"

# The vocabulary is closed. Three states record a decision or a debt rather
# than progress, and carry a mandatory note: a ruling without its reason is
# what a findings file already fails to preserve.
REGISTER_STATES='open planned doing verify done deferred n/a'
REGISTER_UNRESOLVED='open planned doing verify'
REGISTER_NOTE_REQUIRED='verify deferred n/a'

# A cell may hold an escaped pipe. Every parse swaps \| for \001 before
# splitting and swaps it back after, so a note may contain one.
_REGISTER_AWK='
function reg_cells(line, f,   n, i) {
  gsub(/^[ \t]+|[ \t]+$/, "", line)
  if (substr(line, 1, 1) != "|") return 0
  gsub(/\\\|/, "\001", line)
  n = split(line, f, "|")
  for (i = 1; i <= n; i++) {
    gsub(/^[ \t]+|[ \t]+$/, "", f[i])
    gsub(/\001/, "|", f[i])
  }
  return n
}
'

# register_field FILE LABEL — the first "**LABEL:**" value outside fences.
register_field() {
  tr -d '\r' < "$1" | awk -v p="**$2:**" "$_PLAN_AWK"'
    stop { next }
    in_fence($0) { next }
    index($0, p) == 1 {
      v = substr($0, length(p) + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      print v
      stop = 1
    }
  '
  return 0
}

# register_scan FILE — every candidate row line outside fences, as
# "lineno<TAB>fieldcount<TAB>id<TAB>item<TAB>assigned<TAB>acceptance<TAB>state<TAB>note".
# The header and separator rows are dropped; everything else is reported so
# that `register check` can name a malformed row by its line.
register_scan() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK$_REGISTER_AWK"'
    in_fence($0) { next }
    {
      n = reg_cells($0, c)
      if (n == 0) next
      if (c[2] == "#" || c[2] ~ /^:?-+:?$/) next
      printf "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", NR, n, c[2], c[3], c[4], c[5], c[6], c[7]
    }
  '
  return 0
}

# register_rows FILE — the well-formed rows, as
# "id<TAB>item<TAB>assigned<TAB>acceptance<TAB>state<TAB>note".
register_rows() {
  register_scan "$1" | awk -F'\t' '$2 == 8 && $3 ~ /^[0-9]+$/ {
    print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8
  }'
  return 0
}

# register_open FILE — the rows whose state is unresolved.
register_open() {
  register_rows "$1" | awk -F'\t' -v u=" $REGISTER_UNRESOLVED " 'index(u, " " $5 " ") > 0'
  return 0
}

# register_covers FILE — one repository-relative spec path per line; nothing
# when the register covers no spec yet.
register_covers() {
  local value
  value=$(register_field "$1" Covers)
  [ -n "$value" ] && [ "$value" != "-" ] || return 0
  printf '%s' "$value" | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^`//' -e 's/`$//' \
    | grep -v '^$'
  return 0
}

# register_files ROOT — every register in the repository.
register_files() {
  local dir="$1/docs/superpowers/registers" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f"
  done
  return 0
}

# register_for_spec ROOT SPEC... — the registers covering any of the given
# specs. Resolution runs this way round so that a plan cannot carry a stale
# pointer to a register.
register_for_spec() {
  local root="$1" f cov want
  shift
  [ $# -gt 0 ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r cov; do
      [ -n "$cov" ] || continue
      cov=${cov#./}
      for want in "$@"; do
        want=${want#./}
        if [ "$cov" = "$want" ]; then
          printf '%s\n' "$f"
          break 2
        fi
      done
    done < <(register_covers "$f")
  done < <(register_files "$root")
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/register.test.sh`
Expected: PASS — `16 passed, 0 failed`. The count is the assertions this step writes; a lower number means part of the block was not transcribed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/register.sh plugins/dr-superpowers/tests/register.test.sh
git commit -m "feat(superpowers): add register parsing library"
```

---

### Task 2: `register check`

**Files:**
- Create: `plugins/dr-superpowers/scripts/register`
- Modify: `plugins/dr-superpowers/tests/register.test.sh` (append)

**Interfaces:**
- Consumes: `register_field`, `register_scan`, `register_covers`, `REGISTER_STATES`, `REGISTER_NOTE_REQUIRED` — see Contracts.
- Produces: `scripts/register check` and its exit codes, and the `state_known` / `note_required` helpers that Task 4 reuses in the same file.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/register.test.sh`, immediately before the final `printf '\n%d passed…` line:

```bash
# --- register check ---
REG="$HERE/../scripts/register"
run() { # run <args...> -> sets OUT and RC
  OUT=$("$@" 2>&1); RC=$?
}

reg "$ROOT/clean.md" \
  '| 1 | First | - | - | open | - |' \
  '| 2 | Second | - | - | deferred | not this batch |'
run bash "$REG" check "$ROOT/clean.md"
check "check: a clean register" "$RC" "0"
check "check: clean summary" "$(tail -n 1 <<<"$OUT")" "register: 0 errors"

reg "$ROOT/dup.md" '| 1 | A | - | - | open | - |' '| 1 | B | - | - | open | - |'
run bash "$REG" check "$ROOT/dup.md"
check "check: duplicate identifier fails" "$RC" "1"
check "check: names the duplicate" "$(grep -c 'duplicate identifier: 1' <<<"$OUT")" "1"

reg "$ROOT/state.md" '| 1 | A | - | - | finished | - |'
run bash "$REG" check "$ROOT/state.md"
check "check: unknown state fails" "$RC" "1"
check "check: names the state" "$(grep -c 'unknown state: finished' <<<"$OUT")" "1"

reg "$ROOT/note.md" '| 1 | A | - | - | deferred | - |'
run bash "$REG" check "$ROOT/note.md"
check "check: a ruling without its reason fails" "$RC" "1"
check "check: names the missing note" "$(grep -c 'state deferred needs a note' <<<"$OUT")" "1"

reg "$ROOT/short2.md" '| 1 | A | open |'
run bash "$REG" check "$ROOT/short2.md"
check "check: a short row fails" "$RC" "1"

printf '# No header — item register\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | A | - | - | open | - |\n' > "$ROOT/bare.md"
run bash "$REG" check "$ROOT/bare.md"
check "check: missing Source and Covers fails" "$RC" "1"
check "check: names Source" "$(grep -c 'missing \*\*Source:\*\* line' <<<"$OUT")" "1"

printf '# Ghost — item register\n\n**Source:** s\n**Covers:** docs/superpowers/specs/absent-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | A | - | - | open | - |\n' > "$ROOT/ghost.md"
run bash "$REG" check "$ROOT/ghost.md"
check "check: a Covers path that does not exist fails" "$RC" "1"

run bash "$REG" check "$ROOT/absent-file.md"
check "check: a missing file is usage" "$RC" "2"
run bash "$REG"
check "check: no verb is usage" "$RC" "2"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/register.test.sh`
Expected: FAIL — the `check:` assertions report `RC` 127, `bash: .../scripts/register: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `plugins/dr-superpowers/scripts/register`, executable:

```bash
#!/usr/bin/env bash
# Read and write an item register: the list of source items a body of work must
# answer, and the authority on whether that work is finished.
#
# Every write goes through this script rather than an edit, because a table
# cell hand-edited across a dozen sessions is how a row silently loses its
# state, which is the failure the register exists to prevent.
#
# Usage: register check FILE
#        register open [--root DIR] (--spec SPEC | FILE)
#        register set FILE ID STATE [--note TEXT] [--assigned TEXT] [--acceptance TEXT]
#        register add FILE "ITEM" [--assigned TEXT] [--acceptance TEXT] [--state STATE] [--note TEXT]
# Exit: check 0 clean, 1 errors, 2 usage or missing file
#       open  0 nothing open, 1 rows are open, 2 usage
#       set   0 written, 2 usage, unknown identifier, unknown state, or a
#             missing mandatory note
#       add   0 written, 2 usage or a missing mandatory note
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/register.sh"

usage() {
  cat >&2 <<'USAGE'
usage: register check FILE
       register open [--root DIR] (--spec SPEC | FILE)
       register set FILE ID STATE [--note TEXT] [--assigned TEXT] [--acceptance TEXT]
       register add FILE "ITEM" [--assigned TEXT] [--acceptance TEXT] [--state STATE] [--note TEXT]
USAGE
  exit 2
}

state_known() { case " $REGISTER_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
note_required() { case " $REGISTER_NOTE_REQUIRED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
blank_note() { [ -z "$1" ] || [ "$1" = "-" ]; }

need_file() {
  [ -f "$1" ] || { echo "no such register file: $1" >&2; exit 2; }
}

cmd_check() {
  [ $# -eq 1 ] || usage
  local file=$1 errors=0 root covers line n id item assigned acceptance state note seen=""
  need_file "$file"
  root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || pwd)

  if [ -z "$(register_field "$file" Source)" ]; then
    echo "ERROR 1: missing **Source:** line"
    errors=$((errors + 1))
  fi
  covers=$(register_field "$file" Covers)
  if [ -z "$covers" ]; then
    echo "ERROR 1: missing **Covers:** line"
    errors=$((errors + 1))
  else
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      [ -f "$root/$line" ] && continue
      echo "ERROR 1: Covers path does not exist: $line"
      errors=$((errors + 1))
    done < <(register_covers "$file")
  fi

  while IFS=$'\t' read -r line n id item assigned acceptance state note; do
    if [ "$n" -ne 8 ]; then
      echo "ERROR $line: a row needs six cells, found $((n - 2)); write a literal pipe as \\|"
      errors=$((errors + 1))
      continue
    fi
    case $id in
      ''|*[!0-9]*) echo "ERROR $line: identifier must be a positive integer: $id"; errors=$((errors + 1)); continue ;;
    esac
    [ "$id" -ge 1 ] || { echo "ERROR $line: identifier must be a positive integer: $id"; errors=$((errors + 1)); continue; }
    case " $seen " in
      *" $id "*) echo "ERROR $line: duplicate identifier: $id"; errors=$((errors + 1)) ;;
    esac
    seen="$seen $id"
    if [ -z "$item" ]; then
      echo "ERROR $line: item is empty"
      errors=$((errors + 1))
    fi
    if ! state_known "$state"; then
      echo "ERROR $line: unknown state: ${state:-(empty)}; one of $REGISTER_STATES"
      errors=$((errors + 1))
    elif note_required "$state" && blank_note "$note"; then
      echo "ERROR $line: state $state needs a note"
      errors=$((errors + 1))
    fi
  done < <(register_scan "$file")

  echo "register: $errors errors"
  [ "$errors" -eq 0 ]
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  check) cmd_check "$@" ;;
  *) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x plugins/dr-superpowers/scripts/register && bash plugins/dr-superpowers/tests/register.test.sh`
Expected: PASS — `30 passed, 0 failed` (16 from Task 1 plus the 14 this step appends).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/register plugins/dr-superpowers/tests/register.test.sh
git commit -m "feat(superpowers): add register check"
```

---

### Task 3: `register open` and spec resolution

**Files:**
- Modify: `plugins/dr-superpowers/scripts/register`
- Modify: `plugins/dr-superpowers/tests/register.test.sh` (append)

**Interfaces:**
- Consumes: `register_open`, `register_for_spec` — see Contracts.
- Produces: `scripts/register open`, whose exit status is the gate Task 9's skill instructions rely on.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/register.test.sh`, before the final summary lines:

```bash
# --- register open ---
# The exit status is the gate: 1 means "something is still open", so a caller
# can branch on it without parsing the report.
run bash "$REG" open "$ROOT/clean.md"
check "open: rows open exits 1" "$RC" "1"
check "open: names the row" "$(grep -c '#1 First' <<<"$OUT")" "1"
check "open: a resolved row is not listed" "$(grep -c '#2' <<<"$OUT")" "0"

reg "$ROOT/settled.md" '| 1 | A | - | - | done | - |' '| 2 | B | - | - | n/a | answered inline |'
run bash "$REG" open "$ROOT/settled.md"
check "open: nothing open exits 0" "$RC" "0"

run bash "$REG" open --root "$ROOT" --spec docs/superpowers/specs/a-design.md
check "open: by spec finds the covering register" "$RC" "1"
check "open: by spec names the item" "$(grep -c ' A' <<<"$OUT")" "1"

# c-design.md is named by no register: the reg() helper's Covers line lists
# a-design.md and b-design.md, so either of those would match one.
run bash "$REG" open --root "$ROOT" --spec docs/superpowers/specs/c-design.md
check "open: a spec no register covers exits 0" "$RC" "0"

run bash "$REG" open --root "$ROOT" --spec docs/superpowers/specs/a-design.md "$ROOT/clean.md"
check "open: --spec with a file is usage" "$RC" "2"
run bash "$REG" open
check "open: neither --spec nor a file is usage" "$RC" "2"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/register.test.sh`
Expected: FAIL — `open:` assertions get `RC` 2 from `usage`, since the verb is not handled

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/register`, add `cmd_open` directly below `cmd_check`:

```bash
cmd_open() {
  local root="" spec="" file="" found=0 f rel id item assigned acceptance state note
  while [ $# -gt 0 ]; do
    case $1 in
      --root) [ $# -ge 2 ] || usage; root=$2; shift 2 ;;
      --spec) [ $# -ge 2 ] || usage; spec=$2; shift 2 ;;
      -*) usage ;;
      *) [ -z "$file" ] || usage; file=$1; shift ;;
    esac
  done
  if [ -n "$spec" ]; then
    [ -z "$file" ] || usage
    [ -n "$root" ] || root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  else
    [ -n "$file" ] || usage
    need_file "$file"
  fi

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel=$f
    [ -z "$root" ] || rel=${f#"$root"/}
    while IFS=$'\t' read -r id item assigned acceptance state note; do
      found=1
      printf '%s: #%s %s — %s, assigned %s\n' "$rel" "$id" "$item" "$state" "${assigned:--}"
    done < <(register_open "$f")
  done < <(if [ -n "$spec" ]; then register_for_spec "$root" "$spec"; else printf '%s\n' "$file"; fi)

  [ "$found" -eq 0 ]
}
```

And extend the verb dispatch:

```bash
case $verb in
  check) cmd_check "$@" ;;
  open) cmd_open "$@" ;;
  *) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/register.test.sh`
Expected: PASS — `39 passed, 0 failed` (30 plus the 9 this step appends).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/register plugins/dr-superpowers/tests/register.test.sh
git commit -m "feat(superpowers): add register open"
```

---

### Task 4: `register set` and `register add`

**Files:**
- Modify: `plugins/dr-superpowers/scripts/register`
- Modify: `plugins/dr-superpowers/tests/register.test.sh` (append)

**Interfaces:**
- Consumes: `_PLAN_AWK`, `_REGISTER_AWK`, `register_rows`, `register_scan`, `state_known`, `note_required` — see Contracts.
- Produces: `scripts/register set` and `scripts/register add`, the only writers of a register. Tasks 9, 10 and 11 instruct skills to call them.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/register.test.sh`, before the final summary lines:

```bash
# --- register set and add ---
reg "$ROOT/w.md" '| 1 | First | - | - | open | - |' '| 2 | Second | C2 | live check | planned | - |'

run bash "$REG" set "$ROOT/w.md" 1 done
check "set: writes the state" "$RC" "0"
check "set: the row is done" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 1 { print $5 }')" "done"
check "set: the item survives" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 1 { print $2 }')" "First"

run bash "$REG" set "$ROOT/w.md" 2 verify
check "set: verify without a note is refused" "$RC" "2"
run bash "$REG" set "$ROOT/w.md" 2 verify --note "owner live check owed"
check "set: verify with a note is written" "$RC" "0"
check "set: the note is stored" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $6 }')" "owner live check owed"
check "set: the assignment survives" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $3 }')" "C2"

run bash "$REG" set "$ROOT/w.md" 2 planned --assigned docs/superpowers/plans/p.md
check "set: reassigns" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $3 }')" "docs/superpowers/plans/p.md"
check "set: a kept note survives a state change" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $6 }')" "owner live check owed"

run bash "$REG" set "$ROOT/w.md" 9 done
check "set: an unknown identifier is refused" "$RC" "2"
run bash "$REG" set "$ROOT/w.md" 1 finished
check "set: an unknown state is refused" "$RC" "2"

run bash "$REG" add "$ROOT/w.md" "Discovered during execution"
check "add: appends" "$RC" "0"
check "add: takes the next identifier" "$(register_rows "$ROOT/w.md" | cut -f1 | tr '\n' ' ')" "1 2 3 "
check "add: defaults to open" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 3 { print $5 }')" "open"
check "add: stores the item" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 3 { print $2 }')" "Discovered during execution"

run bash "$REG" add "$ROOT/w.md" "Ruled out" --state deferred
check "add: deferred without a note is refused" "$RC" "2"
run bash "$REG" add "$ROOT/w.md" "Ruled out" --state deferred --note "disproportionate for this batch"
check "add: deferred with a note is written" "$RC" "0"
check "add: identifiers keep climbing" "$(register_rows "$ROOT/w.md" | cut -f1 | tr '\n' ' ')" "1 2 3 4 "

run bash "$REG" add "$ROOT/w.md" "Holds a | pipe"
check "add: a pipe is escaped on write" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 5 { print $2 }')" "Holds a | pipe"
run bash "$REG" check "$ROOT/w.md"
check "add: the written register still checks clean" "$RC" "0"

# An empty table still accepts the first row.
printf '# E — item register\n\n**Source:** s\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n\n## Notes\n\nTrailing prose.\n' > "$ROOT/empty.md"
run bash "$REG" add "$ROOT/empty.md" "The first item"
check "add: the first row of an empty table" "$(register_rows "$ROOT/empty.md" | cut -f1)" "1"
check "add: trailing prose survives" "$(tail -n 1 "$ROOT/empty.md")" "Trailing prose."
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/register.test.sh`
Expected: FAIL — the `set:` and `add:` assertions get `RC` 2 from `usage`

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/register`, add both commands below `cmd_open`:

```bash
# Free text reaches awk through the environment, not -v, which would process
# backslash escapes in an item or a note.
cmd_set() {
  [ $# -ge 3 ] || usage
  local file=$1 id=$2 state=$3
  shift 3
  local note="" assigned="" acceptance="" note_given=0 assigned_given=0 acceptance_given=0 row tmp
  while [ $# -gt 0 ]; do
    case $1 in
      --note) [ $# -ge 2 ] || usage; note=$2 note_given=1; shift 2 ;;
      --assigned) [ $# -ge 2 ] || usage; assigned=$2 assigned_given=1; shift 2 ;;
      --acceptance) [ $# -ge 2 ] || usage; acceptance=$2 acceptance_given=1; shift 2 ;;
      *) usage ;;
    esac
  done
  need_file "$file"
  state_known "$state" || { echo "unknown state: $state; one of $REGISTER_STATES" >&2; exit 2; }
  row=$(register_rows "$file" | awk -F'\t' -v i="$id" '$1 == i')
  [ -n "$row" ] || { echo "no row with identifier $id in $file" >&2; exit 2; }
  [ "$note_given" -eq 1 ] || note=$(cut -f6 <<<"$row")
  if note_required "$state" && blank_note "$note"; then
    echo "state $state needs --note" >&2
    exit 2
  fi

  tmp=$(mktemp)
  tr -d '\r' < "$file" | REG_STATE="$state" REG_NOTE="$note" REG_ASSIGNED="$assigned" REG_ACCEPT="$acceptance" \
    awk -v want="$id" -v ag="$assigned_given" -v kg="$acceptance_given" "$_PLAN_AWK$_REGISTER_AWK"'
      function esc(s) { gsub(/\|/, "\\|", s); return s }
      { if (in_fence($0)) { print; next } }
      {
        n = reg_cells($0, c)
        if (n != 8 || c[2] != want) { print; next }
        a = (ag == "1") ? ENVIRON["REG_ASSIGNED"] : c[4]
        k = (kg == "1") ? ENVIRON["REG_ACCEPT"] : c[5]
        printf "| %s | %s | %s | %s | %s | %s |\n", c[2], esc(c[3]), esc(a), esc(k), ENVIRON["REG_STATE"], esc(ENVIRON["REG_NOTE"])
      }
    ' > "$tmp" || { rm -f "$tmp"; echo "could not rewrite $file" >&2; exit 2; }
  mv "$tmp" "$file"
}

cmd_add() {
  [ $# -ge 2 ] || usage
  local file=$1 item=$2
  shift 2
  local assigned="-" acceptance="-" state="open" note="-" max id at tmp
  while [ $# -gt 0 ]; do
    case $1 in
      --assigned) [ $# -ge 2 ] || usage; assigned=$2; shift 2 ;;
      --acceptance) [ $# -ge 2 ] || usage; acceptance=$2; shift 2 ;;
      --state) [ $# -ge 2 ] || usage; state=$2; shift 2 ;;
      --note) [ $# -ge 2 ] || usage; note=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  need_file "$file"
  [ -n "$item" ] || usage
  state_known "$state" || { echo "unknown state: $state; one of $REGISTER_STATES" >&2; exit 2; }
  if note_required "$state" && blank_note "$note"; then
    echo "state $state needs --note" >&2
    exit 2
  fi

  max=$(register_rows "$file" | awk -F'\t' '$1 + 0 > m { m = $1 + 0 } END { print m + 0 }')
  id=$((max + 1))
  # Insert after the last table line rather than at end of file, so a register
  # that carries prose below its table keeps it.
  at=$(tr -d '\r' < "$file" | awk "$_PLAN_AWK"'
    { if (in_fence($0)) next }
    /^[ \t]*\|/ { n = NR }
    END { print n + 0 }')
  [ "$at" -gt 0 ] || { echo "no table in $file" >&2; exit 2; }

  tmp=$(mktemp)
  tr -d '\r' < "$file" | REG_ITEM="$item" REG_ASSIGNED="$assigned" REG_ACCEPT="$acceptance" \
    REG_STATE="$state" REG_NOTE="$note" \
    awk -v at="$at" -v id="$id" '
      function esc(s) { gsub(/\|/, "\\|", s); return s }
      { print }
      NR == at {
        printf "| %s | %s | %s | %s | %s | %s |\n", id, esc(ENVIRON["REG_ITEM"]), \
          esc(ENVIRON["REG_ASSIGNED"]), esc(ENVIRON["REG_ACCEPT"]), ENVIRON["REG_STATE"], esc(ENVIRON["REG_NOTE"])
      }
    ' > "$tmp" || { rm -f "$tmp"; echo "could not rewrite $file" >&2; exit 2; }
  mv "$tmp" "$file"
}
```

Replace the verb dispatch with:

```bash
case $verb in
  check) cmd_check "$@" ;;
  open) cmd_open "$@" ;;
  set) cmd_set "$@" ;;
  add) cmd_add "$@" ;;
  *) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/register.test.sh`
Expected: PASS — `61 passed, 0 failed` (39 plus the 22 this step appends).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/register plugins/dr-superpowers/tests/register.test.sh
git commit -m "feat(superpowers): add register set and add"
```

---

### Task 5: Register-aware completion in `next-step`

**Files:**
- Modify: `plugins/dr-superpowers/scripts/next-step:40` (source line) and `:174-196` (the completion branch)
- Modify: `plugins/dr-superpowers/tests/next-step.test.sh` (append)

**Interfaces:**
- Consumes: `register_for_spec`, `register_open` — see Contracts.
- Produces: the completion output strings in Contracts, which `latest.md` and every resuming session read.

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/next-step.test.sh`, before its final summary lines. Match the file's existing fixture helpers: if it already defines a repository and a plan, reuse them; otherwise build one as below.

```bash
# --- item registers outrank the Program line ---
# The frozen `next:` is copied when the plan is written, so a sub-project split
# decided later never reaches it. A register with an open row must stop the
# "every sub-project is done" answer.
RREPO="$TMP/registers"
git init -q -b main "$RREPO"
mkdir -p "$RREPO/docs/superpowers/plans" "$RREPO/docs/superpowers/specs" "$RREPO/docs/superpowers/registers"
printf '.superpowers/\n' > "$RREPO/.gitignore"
: > "$RREPO/docs/superpowers/specs/prog-design.md"
cat > "$RREPO/docs/superpowers/plans/c1.md" <<'PLAN'
# C1

**Goal:** One
**Spec:** docs/superpowers/specs/prog-design.md
**Execution:** inline — `claude --model sonnet --effort high` — small
**Program:** `docs/superpowers/specs/prog-design.md` — sub-project 3 of 4 — last

### Task 1: One
PLAN
git -C "$RREPO" add -A && git -C "$RREPO" commit -qm init

cat > "$RREPO/docs/superpowers/registers/prog.md" <<'REG'
# Programme — item register

**Source:** owner list 2026-09-18
**Covers:** docs/superpowers/specs/prog-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Status bar | - | - | done | - |
| 4 | Settings tabs | C2 Settings | Radius follows the axis | planned | - |
| 6 | Editor preview | C2 Settings | - | planned | - |
| 16 | Stale note | C2 Settings | - | planned | - |
| 17 | Unused UI font | C2 Settings | - | planned | - |
REG

OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: a register with open rows refuses 'Nothing'" "$OUT" "Register rows still open (4) in \`docs/superpowers/registers/prog.md\`"
has "next-step: names the first rows" "$OUT" "#4 Settings tabs"
has "next-step: caps the list at three" "$OUT" "+1 more"
has "next-step: routes to the assignment" "$OUT" "\`C2 Settings\`: write its spec in a fresh session."
lacks "next-step: must not claim the program is done" "$OUT" "Nothing — every sub-project"

# An unassigned row routes to brainstorming instead.
bash "$HERE/../scripts/register" set "$RREPO/docs/superpowers/registers/prog.md" 4 open --assigned -
bash "$HERE/../scripts/register" set "$RREPO/docs/superpowers/registers/prog.md" 6 done
bash "$HERE/../scripts/register" set "$RREPO/docs/superpowers/registers/prog.md" 16 done
bash "$HERE/../scripts/register" set "$RREPO/docs/superpowers/registers/prog.md" 17 done
OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: an unassigned row routes to brainstorming" "$OUT" "Rule on the open rows with dr-superpowers:brainstorming."
has "next-step: one row still reports" "$OUT" "Register rows still open (1) in"

# Every row resolved: the Program line answers again, exactly as before.
bash "$HERE/../scripts/register" set "$RREPO/docs/superpowers/registers/prog.md" 4 done
OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: a fully resolved register restores the old answer" "$OUT" "Nothing — every sub-project"

# No register at all: unchanged behaviour, which is what keeps every existing
# plan in this repository working.
rm "$RREPO/docs/superpowers/registers/prog.md"
OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: no register means no change" "$OUT" "Nothing — every sub-project"
```

`tests/next-step.test.sh` already defines `SCRIPT`, `TMP`, `has` and `lacks`; reuse them rather than redefining any of them.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/next-step.test.sh`
Expected: FAIL — the register assertions report the old `Nothing — every sub-project of … is done` answer

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/next-step`, source the library beside `lib/plan.sh` (line 40):

```bash
. "$(cd "$(dirname "$0")" && pwd)/lib/plan.sh"
. "$(cd "$(dirname "$0")" && pwd)/lib/register.sh"
```

Then replace the completion branch — everything from `if [ "$complete" -eq 1 ]; then` down to the `fi` that closes its inner chain — with:

```bash
  if [ "$complete" -eq 1 ]; then
    spec=$(sed -E 's/^\*\*Program:\*\*[ \t]*`?([^` \t]+)`?.*/\1/' <<<"$program")
    k=$(grep -oE 'sub-project [0-9]+ of [0-9]+' <<<"$program" | head -n 1 | awk '{print $2}' || true)
    n=$(grep -oE 'sub-project [0-9]+ of [0-9]+' <<<"$program" | head -n 1 | awk '{print $4}' || true)
    next_title=$(sed -nE 's/.*( — | – | - | -- )next:[ \t]*(.*[^ \t])[ \t]*$/\2/p' <<<"$program")
    launch=0

    # An item register outranks the Program line. `next:` is copied from the
    # program's decomposition when the plan is written, so a split decided in a
    # child spec never reaches it, and `last` alone cannot end a programme.
    reg_specs=()
    plan_spec=$(sed -E 's/^\*\*Spec:\*\*[ \t]*`?([^` \t]+)`?.*/\1/' <<<"$(plan_header_line "$plan" Spec)")
    [ -z "$plan_spec" ] || reg_specs+=("$plan_spec")
    [ -z "$spec" ] || [ "$spec" = "$plan_spec" ] || reg_specs+=("$spec")
    open_rows="" reg_list=""
    if [ ${#reg_specs[@]} -gt 0 ]; then
      while IFS= read -r reg_file; do
        [ -n "$reg_file" ] || continue
        rows=$(register_open "$reg_file")
        [ -n "$rows" ] || continue
        # Several registers may cover one spec; every one that has open rows is
        # named, so the count is never attributed to the wrong file.
        reg_list="${reg_list:+$reg_list, }\`${reg_file#"$root"/}\`"
        open_rows="${open_rows}${rows}
"
      done < <(register_for_spec "$root" "${reg_specs[@]}")
    fi
    open_rows=$(grep . <<<"$open_rows" || true)

    if [ -n "$open_rows" ]; then
      open_n=$(grep -c . <<<"$open_rows")
      row_list=$(awk -F'\t' '
        NR <= 3 { printf "%s#%s %s", (NR > 1 ? "; " : ""), $1, $2 }
        END { if (NR > 3) printf " +%d more", NR - 3 }
      ' <<<"$open_rows")
      assigned=$(head -n 1 <<<"$open_rows" | cut -f3)
      if [ -n "$assigned" ] && [ "$assigned" != "-" ]; then
        action="\`$assigned\`: write its spec in a fresh session."
      else
        action="Rule on the open rows with dr-superpowers:brainstorming."
      fi
      status_line="Plan \`$rel\` is complete."
      next_line="Register rows still open ($open_n) in $reg_list: $row_list. $action"
      launch_cmd=$(launch_for design)
      prompt="Continue the work recorded in $reg_list: $open_n rows are open ($row_list). $action"
      launch=1
    elif [ -z "$program" ]; then
      status_line="Plan \`$rel\` is complete."
      next_line="Nothing — the plan records no follow-on work."
    elif grep -qE '( — | – | - | -- )last[ \t]*$' <<<"$program" || { [ -n "$k" ] && [ "$k" -ge "$n" ]; }; then
      status_line="Plan \`$rel\` is complete${k:+; sub-project $k of $n is done}."
      next_line="Nothing — every sub-project of \`$spec\` is done."
    elif [ -n "$next_title" ] && [ -n "$k" ]; then
      k1=$((k + 1))
      status_line="Plan \`$rel\` is complete; sub-project $k of $n is done."
      next_line="Sub-project $k1 ($next_title): write its spec in a fresh session."
      launch_cmd=$(launch_for design)
      prompt="Start sub-project $k1 ($next_title) of the program in \`$spec\`: use dr-superpowers:brainstorming to write its spec."
      launch=1
    else
      status_line="Plan \`$rel\` is complete."
      next_line="Read \`$spec\` for the sub-project after ${k:-this one} — the plan's Program line names no next step."
    fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/next-step.test.sh && bash plugins/dr-superpowers/tests/register.test.sh`
Expected: PASS — both suites report `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/next-step plugins/dr-superpowers/tests/next-step.test.sh
git commit -m "feat(superpowers): gate next-step on registers"
```

---

### Task 6: Register coverage in `plan-lint`

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint` (source line at `:16`, new section after the Program block at `:78`)
- Modify: `plugins/dr-superpowers/tests/plan-lint.test.sh` (append)

**Interfaces:**
- Consumes: `register_for_spec`, `register_rows`, `register_open`, and `spec_path`, `ppath`, `SEP`, `say`, `TMP`, `src`, `root` from `plan-lint` itself.
- Produces: the `**Items:**` line's meaning, which Task 10 teaches `writing-plans` to emit.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/plan-lint.test.sh`, before its summary lines, following the file's existing fixture style:

```bash
# --- item registers ---
LREPO="$TMP/lint-registers"
git init -q -b main "$LREPO"
mkdir -p "$LREPO/docs/superpowers/plans" "$LREPO/docs/superpowers/specs" "$LREPO/docs/superpowers/registers"
: > "$LREPO/docs/superpowers/specs/s-design.md"
cat > "$LREPO/docs/superpowers/registers/r.md" <<'REG'
# R — item register

**Source:** review 2026-09-20
**Covers:** docs/superpowers/specs/s-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Covered | docs/superpowers/plans/p.md | - | planned | - |
| 2 | Someone else's | C2 | - | planned | - |
REG

write_plan() { # write_plan <program-suffix> <items-line>
  cat > "$LREPO/docs/superpowers/plans/p.md" <<PLAN
# P Implementation Plan

**Goal:** g
**Spec:** docs/superpowers/specs/s-design.md
**Execution:** inline — \`claude --model sonnet --effort low\` — small
**Program:** \`docs/superpowers/specs/s-design.md\` — sub-project 1 of 2 — $1

## Global Constraints

None.

## Contracts

None.

## Assumptions (evidence)

- none

## Task index

1. One

---

### Task 1: One

**Files:**
- Create: \`a.txt\`

**Interfaces:**
- Consumes: nothing
- Produces: nothing
$2
**Implementer:** dr-superpowers:impl-haiku
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Do it**

\`\`\`bash
echo hi > a.txt
\`\`\`
PLAN
}

write_plan "next: Two" "**Items:** 1"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
lacks "plan-lint: a cited row is covered" "$OUT" "register row #1"

write_plan "next: Two" ""
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: an uncited assigned row is an error" "$OUT" \
  "ERROR header: register row #1 is assigned to this plan but no task cites it"
has "plan-lint: a plan with no Items line warns" "$OUT" \
  "WARN header: a register covers this plan's spec but no task carries an **Items:** line"

write_plan "next: Two" "**Items:** 1, 9"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: a dangling citation is an error" "$OUT" \
  "ERROR header: **Items:** cites #9, which no covering register holds"

write_plan "last" "**Items:** 1"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: 'last' with another sub-project's open row is an error" "$OUT" \
  "ERROR header: Program line says 'last' while register rows are open: #2"

# A plan with no covering register lints exactly as it did before.
rm "$LREPO/docs/superpowers/registers/r.md"
write_plan "last" ""
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
lacks "plan-lint: no register means no register findings" "$OUT" "register row"
lacks "plan-lint: no register means no premature-last finding" "$OUT" "register rows are open"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/plan-lint.test.sh`
Expected: FAIL — none of the four register findings appear in the output

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/plan-lint`, source the library beside the others near line 16:

```bash
. "$HERE/lib/plan.sh"
. "$HERE/lib/register.sh"
. "$HERE/lib/codex-session.sh"
```

Then insert this section immediately after the Program-line block (after the `fi` that closes `if [ -n "$program" ]; then`):

```bash
# --- item registers ---
# A register is the authority on whether the work is finished; the Program line
# is a pointer. These checks answer both directions of "is every item covered".
reg_specs=()
[ -z "${spec_path:-}" ] || reg_specs+=("$spec_path")
[ -z "${ppath:-}" ] || [ "${ppath:-}" = "${spec_path:-}" ] || reg_specs+=("$ppath")
if [ ${#reg_specs[@]} -gt 0 ]; then
  # git prints the top level as D:/… under Git Bash where pwd prints /d/…, so
  # the path is canonicalised the way lib/plan.sh already does before stripping.
  plan_rel=$(plan_repo_canon "$plan" 2>/dev/null || printf '%s' "$plan")
  plan_rel=${plan_rel#"$root"/}
  : > "$TMP/reg-ids"
  : > "$TMP/reg-open"
  while IFS= read -r reg_file; do
    [ -n "$reg_file" ] || continue
    register_rows "$reg_file" | cut -f1 >> "$TMP/reg-ids"
    register_open "$reg_file" >> "$TMP/reg-open"
  done < <(register_for_spec "$root" "${reg_specs[@]}")

  if [ -s "$TMP/reg-ids" ]; then
    cited=$(awk "$_PLAN_AWK"'
      in_fence($0) { next }
      index($0, "**Items:**") == 1 {
        line = substr($0, 11)
        gsub(/[^0-9]+/, " ", line)
        print line
      }
    ' "$src" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -un || true)

    [ -n "$cited" ] \
      || say WARN header "a register covers this plan's spec but no task carries an **Items:** line"

    while IFS=$'\t' read -r rid ritem rassigned _ _ _; do
      [ "$rassigned" = "$plan_rel" ] || continue
      grep -qx "$rid" <<<"$cited" \
        || say ERROR header "register row #$rid is assigned to this plan but no task cites it"
    done < "$TMP/reg-open"

    for rid in $cited; do
      grep -qx "$rid" "$TMP/reg-ids" \
        || say ERROR header "**Items:** cites #$rid, which no covering register holds"
    done

    if grep -qE "$SEP"'last[ \t]*$' <<<"$program"; then
      others=$(awk -F'\t' -v p="$plan_rel" '$3 != p { printf "%s#%s", (c++ ? ", " : ""), $1 }' "$TMP/reg-open")
      [ -z "$others" ] \
        || say ERROR header "Program line says 'last' while register rows are open: $others"
    fi
  fi
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/plan-lint.test.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): lint register coverage"
```

---

### Task 7: Item registers in `repo-audit`

**Files:**
- Modify: `plugins/dr-superpowers/scripts/repo-audit` (source line at `:12`, new section before `## Handoff`)
- Modify: `plugins/dr-superpowers/tests/repo-audit.test.sh` (append)

**Interfaces:**
- Consumes: `register_files`, `register_rows`, `register_open` — see Contracts.
- Produces: the `## Item registers` section, which `project-status` reads in Task 8.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/repo-audit.test.sh`, before its summary lines:

```bash
# --- item registers ---
OUT=$(cd "$REPO" && bash "$SCRIPT" 2>&1)
has "audit: the section exists" "$OUT" "## Item registers"
# Scoped to the section: "- none" is already printed by Plans in flight and
# Handoff, so an unscoped assertion would pass against a stub.
SECTION=$(sed -n '/## Item registers/,/^$/p' <<<"$OUT")
has "audit: no registers says so" "$SECTION" "- none"

mkdir -p "$REPO/docs/superpowers/registers"
cat > "$REPO/docs/superpowers/registers/r.md" <<'REG'
# R — item register

**Source:** owner list
**Covers:** -

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Done thing | - | - | done | - |
| 2 | Open thing | - | - | planned | - |
| 3 | Owner check | - | live check | verify | owner live check owed |
REG
OUT=$(cd "$REPO" && bash "$SCRIPT" 2>&1)
has "audit: counts open rows" "$OUT" "2 open"
has "audit: counts rows awaiting the owner" "$OUT" "1 awaiting your check"
has "audit: counts the whole register" "$OUT" "of 3 rows"
has "audit: names the register" "$OUT" "docs/superpowers/registers/r.md"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/repo-audit.test.sh`
Expected: FAIL — `missing: [## Item registers]`

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/repo-audit`, source the library beside `lib/plan.sh` (line 12):

```bash
. "$here/lib/plan.sh"
. "$here/lib/register.sh"
```

Insert this block immediately before the `## Handoff` section:

```bash
echo
echo "## Item registers"
reg_found=0
while IFS= read -r reg_file; do
  [ -n "$reg_file" ] || continue
  reg_found=1
  reg_rel=${reg_file#"$root"/}
  reg_total=$(register_rows "$reg_file" | grep -c . || true)
  reg_open=$(register_open "$reg_file" | grep -c . || true)
  reg_verify=$(register_open "$reg_file" | awk -F'\t' '$5 == "verify"' | grep -c . || true)
  echo "- \`$reg_rel\` — $reg_open open ($reg_verify awaiting your check) of $reg_total rows"
done < <(register_files "$root")
[ "$reg_found" -eq 1 ] || echo "- none"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/repo-audit.test.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/repo-audit plugins/dr-superpowers/tests/repo-audit.test.sh
git commit -m "feat(superpowers): audit item registers"
```

---

### Task 8: Registers in `project-status`

**Files:**
- Modify: `plugins/dr-superpowers/skills/project-status/SKILL.md:37-39` and its report shape
- Modify: `plugins/dr-superpowers/reference/project-state.md:27-41`
- Modify: `plugins/dr-superpowers/tests/project-status.test.sh` (append)

**Interfaces:**
- Consumes: the `## Item registers` section from Task 7.
- Produces: nothing other tasks read.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/project-status.test.sh`, before its summary lines:

```bash
# --- item registers ---
# Every needle below sits on one source line in the skill: these assert with
# grep -F, and a phrase the file wraps can never match.
SKILL="$P/skills/project-status/SKILL.md"
present "status: names the registers directory" "$SKILL" "docs/superpowers/registers/"
present "status: completed.md is no longer the only completion signal" "$SKILL" \
  "not whether the work is finished"
present "status: a register can veto done" "$SKILL" \
  "Never report work complete while a covering register has an unresolved row"
present "status: the report has an open-items section" "$SKILL" "**Open items**"
present "status: verify rows are the owner's" "$SKILL" "awaiting your check"
present "status: six sections now" "$SKILL" "Six sections, in this order"
present "state: registers are listed" "$STATE" "docs/superpowers/registers/"
if grep -qF "is the only completion signal" "$SKILL"; then
  printf 'FAIL - status: the old single-source rule is gone\n'; fail=$((fail + 1))
else
  printf 'ok   - status: the old single-source rule is gone\n'; pass=$((pass + 1))
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: FAIL — seven `missing:` reports, and the old-rule check fails

- [ ] **Step 3: Write the implementation**

In `skills/project-status/SKILL.md`, replace the Complete bullet. Keep the
second line whole: the suite asserts against it with `grep -F`.

```markdown
   - **Complete** — listed in `docs/superpowers/plans/completed.md`. That index
     answers whether the branch landed, not whether the work is finished: an
     item register answers that. A ledger showing every task complete is not a
     completion signal either — the work may be unmerged.
```

Add a step after the constraints step (renumbering the Report step). Transcribe
it exactly as written — the final line is asserted whole with `grep -F`:

```markdown
7. **Read the item registers.** Every `docs/superpowers/registers/*.md` the
   audit lists. Unresolved rows — `open`, `planned`, `doing`, `verify` — are
   open work whatever the plans say, and a register whose `**Covers:**` is `-`
   is a list that arrived before anything was designed, which is open work too.
   Never report work complete while a covering register has an unresolved row.
```

In the Output section, change `Five sections, in this order, nothing else:` to
`Six sections, in this order, nothing else:` and add this bullet directly above
**Next step**, after **Owner-only items**:

```markdown
- **Open items** — per register, its unresolved rows as `#<id> <item> —
  <state>`. Rows at `verify` sit under a sub-heading reading awaiting your check:
  they are built, and only your human partner closes them.
```

`verify` rows appear here and nowhere else. **Owner-only items** keeps what it
already holds — `BLOCKED` tasks and rulings waiting on a decision — so the two
sections do not overlap.

The suite at `tests/project-status.test.sh:71-74` pins the report's section
order with an alternation that does not yet know about this section. Add
`Open items` to both the regex and the expected string, between
`Owner-only items` and `Next step`, and change the comment above it from "The
five output sections, in order." to "The six output sections, in order."

In `reference/project-state.md`, add to the file list and the table:

```markdown
- `docs/superpowers/registers/*.md`
```

```markdown
| `registers/*.md` | dr-superpowers:brainstorming, dr-superpowers:writing-plans, both execution skills, dr-superpowers:finishing-a-development-branch — all through `scripts/register` | `scripts/next-step`, `scripts/plan-lint`, `scripts/repo-audit`, dr-superpowers:project-status, dr-superpowers:brainstorming |
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/project-status/SKILL.md plugins/dr-superpowers/reference/project-state.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "docs(superpowers): read registers in status"
```

---

### Task 9: Resolving rows in `finishing-a-development-branch`

**Files:**
- Modify: `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md:93-98` and `:234-245`
- Test: `plugins/dr-superpowers/tests/project-status.test.sh` (append)

**Interfaces:**
- Consumes: `scripts/register open`, `set` and `add` — see Contracts.
- Produces: nothing other tasks read.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/project-status.test.sh`, before its summary lines (the suite already pins prose across these skills):

```bash
# --- finishing resolves register rows ---
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
present "finishing: the register gates the completion line" "$FIN" \
  "Only when every covering register is fully resolved"
present "finishing: an unresolved register changes the line" "$FIN" \
  "After integration: <n> register rows are still open"
present "finishing: rows are resolved through the script" "$FIN" "scripts/register set"
present "finishing: discovered work becomes a row" "$FIN" "scripts/register add"
present "finishing: verify is the owner's state" "$FIN" \
  "a check only your human partner can perform"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: FAIL — five `missing:` reports against the finishing skill

- [ ] **Step 3: Write the implementation**

In `skills/finishing-a-development-branch/SKILL.md`, replace the paragraph above the Step 5 menu:

```markdown
Directly above the menu, write one line saying what follows the plan. Run
`scripts/register open --spec <the plan's Spec path>` first. While it exits 1,
the line is `After integration: <n> register rows are still open — #<id>
<item>`, whatever the Program line says.

Only when every covering register is fully resolved does the Program line
answer, read as before: `After integration: sub-project <k+1> (<title>) of
<spec>` when it names `next: <title>`, `After integration: the program is
complete` when it is the last sub-project, and `After integration: no
follow-on work recorded` when there is no Program line or no plan. Step 7 turns
this into the launch block once the choice is made.
```

Replace the "Carry open findings with it" paragraph in Step 5b:

```markdown
**Carry open findings with it.** The ledger is the only record of what the run
left open, and Step 6 deletes it.

When a register covers this plan's spec, it is where open work lives, and the
prose note is not written. In the same commit as the index line:

- resolve every row this plan covered — one its tasks cite, or one whose
  `Assigned` cell is this plan's path — with
  `scripts/register set <register> <id> done`, or `verify --note <what is owed>`
  when the row's acceptance names a check only your human partner can perform;
- add a row for every `minor (deferred)` line, every `parked` line, every
  complete line's `discovered:` field that is not `none`, and every final-review
  finding you left for your human partner, with
  `scripts/register add <register> "<item>"` — `--state deferred --note <the
  ruling>` when it is not work anyone will do, plain `open` when it is.

When no register covers the plan, write
`docs/superpowers/notes/<slug>-followups.md` instead, listing those same
findings one bullet each with its task number. Write nothing when all of them
are empty. Either artifact travels with the same outcomes as the index line:
Options 1 and 2 only.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "docs(superpowers): resolve rows at finishing"
```

---

### Task 10: Opening registers in `brainstorming` and `writing-plans`

**Files:**
- Modify: `plugins/dr-superpowers/skills/brainstorming/SKILL.md` (the architectural checklist and "Understanding the idea")
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md` (the Task Structure block and a new rule)
- Modify: `plugins/dr-superpowers/tests/project-status.test.sh` (append)

**Interfaces:**
- Consumes: `scripts/register add`, `set`, `check`; the `**Items:**` grammar Task 6 enforces.
- Produces: nothing other tasks read.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/project-status.test.sh`, before its summary lines:

```bash
# --- the design surfaces open and assign rows ---
BRAIN="$P/skills/brainstorming/SKILL.md"
PLANS="$P/skills/writing-plans/SKILL.md"
present "brainstorming: the trigger is two or more items" "$BRAIN" \
  "two or more distinct items"
present "brainstorming: the register comes before the spec" "$BRAIN" \
  "docs/superpowers/registers/YYYY-MM-DD-<slug>.md"
present "brainstorming: an existing register is read first" "$BRAIN" \
  "scripts/register open"
present "writing-plans: rows are assigned" "$PLANS" "scripts/register set"
present "writing-plans: tasks cite rows" "$PLANS" "**Items:**"
present "writing-plans: a design-time deferral becomes a row" "$PLANS" \
  "deferred"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: FAIL — six `missing:` reports

- [ ] **Step 3: Write the implementation**

In `skills/brainstorming/SKILL.md`, add a bullet to "Understanding the idea", after the `constraints.md` bullet:

```markdown
- Run `scripts/register open --spec <any spec this work touches>` and read every
  register covering the area. A row deferred months ago is a decision this
  design inherits; a findings file nobody reopens is how it was lost before.
```

Add a first item to the Architectural checklist, renumbering the rest:

```markdown
1. **Open the item register** — when the request or a review carries two or
   more distinct items, before the spec
```

And add a subsection after "Understanding the idea":

```markdown
**Opening an item register:**

When a request, a review or a batch arrives carrying two or more distinct items,
write them down before designing anything. Create
`docs/superpowers/registers/YYYY-MM-DD-<slug>.md` with a `**Source:**` line
naming where the items came from, a `**Covers:**` line holding `-` until a spec
exists, and the table header
`| # | Item | Assigned | Acceptance | State | Note |`. Add each item with
`scripts/register add <file> "<the requester's words>"` — their words, not your
paraphrase — and confirm the file with `scripts/register check <file>`.

The register is the authority on whether the work is finished. A list that
lives only in the conversation is a list that gets shorter every session.
```

In `skills/writing-plans/SKILL.md`, add `**Items:**` to the Task Structure block, directly below the `**Interfaces:**` block:

```markdown
**Items:** [only when a register covers this plan's spec: the register row
identifiers this task discharges, comma-separated, for example `4, 16`. Omit
the line otherwise.]
```

The assignment lines then follow the Items line rather than the Interfaces
block. Amend `writing-plans/SKILL.md:232`, which reads exactly:

```markdown
5. **Write the lines** directly below the task's `**Interfaces:**` block, in
```

to:

```markdown
5. **Write the lines** directly below the task's `**Items:**` line, or its
   `**Interfaces:**` block when there is no Items line, in
```

And add a section immediately after "Assign an implementer to every task":

```markdown
## Assign the register rows

When a register covers this plan's spec, the plan is where its rows become
work.

1. Set every row this plan schedules with
   `scripts/register set <register> <id> planned --assigned <this plan's
   repository-relative path>`, and give it an `--acceptance` if it has none:
   that cell is what lets finishing decide between `done` and `verify`.
2. Put the identifiers on the tasks that discharge them, as `**Items:**` lines.
3. Record a deferral as a row, not as prose. An item this plan will not answer
   is `scripts/register set <register> <id> deferred --note "<the reason>"`. An
   "Out of scope" heading is read by nothing, which is how design-time
   deferrals were lost.

`plan-lint` then checks both directions: an assigned row no task cites, and a
task citing a row no register holds.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/brainstorming/SKILL.md plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "docs(superpowers): open registers when designing"
```

---

### Task 11: Marking rows `doing`, and the documentation

**Files:**
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` (Setup)
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (Setup)
- Modify: `plugins/dr-superpowers/README.md`
- Modify: `plugins/dr-superpowers/tests/project-status.test.sh` (append)

**Interfaces:**
- Consumes: `scripts/register set` — see Contracts.
- Produces: nothing other tasks read.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/project-status.test.sh`, before its summary lines:

```bash
# --- execution marks rows doing, and the README documents the artifact ---
for skill_file in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md"; do
  present "execution: rows go to doing at the start ($(basename "$(dirname "$skill_file")"))" \
    "$skill_file" "scripts/register set"
done
present "README: the register is documented" "$P/README.md" "docs/superpowers/registers/"
present "README: the states are documented" "$P/README.md" \
  "open, planned, doing, verify, done, deferred, n/a"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: FAIL — four `missing:` reports

- [ ] **Step 3: Write the implementation**

Add this bullet to the Setup section of both `skills/executing-plans/SKILL.md` and `skills/subagent-driven-development/SKILL.md`, after the ledger-creation bullet:

```markdown
- When a register covers this plan's spec, mark the rows this plan carries as
  in flight once, at the start of the run:
  `scripts/register set <register> <id> doing`. The register is read by
  `next-step`, `repo-audit` and dr-superpowers:project-status, so a run that
  never says it started reads as unscheduled work everywhere else.
```

Add a section to `README.md`, beside the existing project-state documentation:

```markdown
### Item registers

A register is the list of source items a body of work must answer, and the
authority on whether that work is finished. One file per incoming list —
an owner's list, a review's findings, a batch — at
`docs/superpowers/registers/YYYY-MM-DD-<slug>.md`, committed, and required
whenever a request carries two or more distinct items.

Each row carries an identifier, the requester's words, an assignment, an
acceptance, a state and a note. The states are
open, planned, doing, verify, done, deferred, n/a
— the first four unresolved, with `verify` meaning built and the owner's
confirmation still owed. A note is mandatory for verify, deferred and n/a,
because those three record a decision rather than progress.

`scripts/register` reads and writes them: `check` validates a file, `open`
reports the unresolved rows for a file or a spec and exits 1 while any remain,
and `set` and `add` are the only writers. Readers resolve a register from a
plan's `**Spec:**` and `**Program:**` spec paths rather than from a pointer in
the plan, so the link cannot go stale.

No surface may claim a body of work complete while a row is unresolved:
`next-step` reports the open rows instead of "every sub-project is done",
`plan-lint` rejects a `last` Program line that a register contradicts, and
`project-status` lists the open rows. When no register covers a spec, every
surface behaves exactly as it did before.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: PASS — `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/executing-plans/SKILL.md plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/README.md plugins/dr-superpowers/tests/project-status.test.sh
git commit -m "docs(superpowers): document item registers"
```

---

### Task 12: First register and the 1.15.0 release

**Files:**
- Create: `docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md`
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json:5`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json:3`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh:560-561` — it pins both manifest versions, so the bump fails the suite until those two lines move with it

**Interfaces:**
- Consumes: `scripts/register check` — see Contracts.
- Produces: the first real register, which proves the format against something that exists.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Run the verification that must hold at the end, and watch it fail:

Run: `bash plugins/dr-superpowers/scripts/register check docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md`
Expected: FAIL — `no such register file`, exit 2

- [ ] **Step 2: Confirm the versions are still the shipped ones**

Run: `grep -h '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json`
Expected: both read `"version": "1.14.0"`

- [ ] **Step 3: Write the implementation**

Create `docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md`. The rows are the three items the review-fixes spec deferred in its §12; they stay unassigned, so `plan-lint` never fires against the merged plan:

```markdown
# Review fixes deferrals — item register

**Source:** deferrals in the 1.11.0 whole-plugin review fixes spec, §12
**Covers:** docs/superpowers/specs/2026-09-17-dr-superpowers-review-fixes-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | M3: a leftover Evaluation line above `#### Part A` is counted by `plan_scores` and `review-route` | - | A split task scores from its part bodies only | open | Over-routes, never under-routes; deferred on 2026-09-17 with no successor recorded |
| 2 | A split-into-parts amendment applied then re-linted has no test | - | `plan-amend` applies a split and `plan-lint` accepts the result, in one test | open | Deferred on 2026-09-17 |
| 3 | No test covers paths with spaces or non-ASCII characters | - | One suite drives a plan under a path with a space and a non-ASCII character | open | Deferred on 2026-09-17 |
```

Then set both manifests to `1.15.0`, and move the suite that pins them in the
same edit — `tests/review-route.test.sh:560-561` assert the shipped version, so
leaving them behind turns the bump into two failing assertions:

```bash
sed -i 's/"version": "1.14.0"/"version": "1.15.0"/' \
  plugins/dr-superpowers/.claude-plugin/plugin.json \
  plugins/dr-superpowers/.codex-plugin/plugin.json
sed -i 's/1\.14\.0/1.15.0/g' plugins/dr-superpowers/tests/review-route.test.sh
```

- [ ] **Step 4: Run the whole verification**

```bash
bash plugins/dr-superpowers/scripts/register check docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md
bash plugins/dr-superpowers/scripts/register open --spec docs/superpowers/specs/2026-09-17-dr-superpowers-review-fixes-design.md
grep -h '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
node scripts/validate-repository.mjs
bash plugins/dr-superpowers/scripts/repo-audit | sed -n '/## Item registers/,/^$/p'
```

Expected: `register: 0 errors`; `open` lists three rows and exits 1; both manifests read `1.15.0`; the validator passes; the audit names the new register with `3 open (0 awaiting your check) of 3 rows`.

Then the plugin manifests, as the repository's CLAUDE.md and spec §12 require, each bounded:

```bash
claude plugin validate .claude-plugin/marketplace.json
claude plugin validate plugins/dr-superpowers
claude plugin validate plugins/dr-status
claude plugin validate plugins/dcc-darkraise-ui
claude plugin validate plugins/dcc-darkraise-win32ui
```

Expected: each reports the manifest valid. Terminate any process these leave behind before continuing.

Then the full suite, bounded, in the background:

Run: `node scripts/test-all.mjs`
Expected: every suite passes except the known pre-existing `tests/ui-discovery.test.mjs` failure (`bash: rg: command not found`).

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): release 1.15.0"
```
