# dr-superpowers Small-Model Planning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use dr-superpowers:subagent-driven-development (the **Execution:** line says `subagent`). Where only the older plugins are enabled, use superpowers:subagent-driven-development with dcc-superpower-companions:dispatching-tiered-implementers. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. Under executing-plans these lines are inert; ignore them.

**Goal:** Ship dr-superpowers 1.4.0: a plan header block every brief carries, `plan-lint`, plan review, append-only amendments through `plan-amend`, a read-only ruling seat that owns every execution judgment call, and the R12 entry point and reinforcement blocks.

**Architecture:** The shared parser `lib/plan.sh` lands first (CommonMark fence rule, header and task extraction, amendment application), then the scripts built on it (`task-brief`, `plan-lint`, `plan-amend`), then the judge templates (plan review, ruling seat), then the skill rewrites that use them (subagent-driven-development, its references, writing-plans, the entry point and brainstorming, the reinforcement blocks), then README, version and full verification.

**Tech Stack:** Bash (Git Bash on Windows) + GNU awk + jq + git; Markdown skills; Node 22 for the repository validator.

**Spec:** `docs/superpowers/specs/2026-09-12-dr-superpowers-small-model-planning-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 1 scores 5 and Tasks 2, 7, 8, 9 score 4, so R5 inline eligibility fails; every task carries its full text for literal execution.

**Program:** docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md — sub-project 4 of 5 — next: Inline mode

**Plan review:** 2026-09-12 — dcc-superpower-companions:judge-fable — executability 17 / coherence 17 / coverage 16 / assumptions 17 (round 2)

Execute in a worktree (using-git-worktrees) branched from `docs/dr-superpowers-fork-design`, which carries the spec and this plan.

## Global Constraints

- Never touch `plugins/darkmem-resume/` (owner's live work) or historical docs under `docs/superpowers/`. Never push. Never merge to main.
- Claude and Codex dr-superpowers manifest versions stay equal: both become `1.4.0` (Task 12). Catalogs are unchanged.
- Literal prefix rule (enforced by `scripts/validate-repository.mjs`): outside `plugins/dr-superpowers/reference/legacy-names.md`, no file under `plugins/` may contain `superpowers:` unless preceded by `dr-`, or `dcc-superpower-companions:`. Test fixtures that need an old prefix build it by string concatenation.
- Reference rule (same validator): every `dr-superpowers:<name>` under `plugins/` must name `plugins/dr-superpowers/skills/<name>/` or `plugins/dr-superpowers/agents/<name>.md`. Every relative Markdown link in a skill must resolve.
- Scripts are Bash with `#!/usr/bin/env bash`, run under Git Bash on Windows, and use only bash, coreutils, GNU awk, git and jq. New executables are added with `git add --chmod=+x`.
- Criteria files are ASCII only (`tests/criteria.test.sh` rejects other bytes).
- `plugins/dr-superpowers/skills/using-superpowers/SKILL.md` is at most 4,800 bytes (`wc -c`).
- Do not modify `reference/ladder.md`, `reference/codex-routing.json`, `reference/native-codex.md`, or any agent file except the two judge `description:` lines in Task 6.
- Commits: `<type>(superpowers): <subject>`, the subject (the text after `): `) ≤50 chars, imperative, English.
- Every test/CLI run is bounded with `timeout`; kill any process you start.
- **Before running any test**, in the same Bash call: `export TMPDIR="$(cygpath -m "$TMP")"`. Claude Code sets `TMPDIR=/tmp`, and suites that export `MSYS_NO_PATHCONV=1` then create their git repositories where native `git.exe` cannot find them (every check fails, "nothing to commit").
- `P` below means `plugins/dr-superpowers`. Paths are relative to the repository root.

## Contracts

- **`P/scripts/lib/plan.sh`** (sourced; all output LF, CR stripped on input; fences by the CommonMark rule: a line matching `^ {0,3}(`{3,}|~{3,})` opens, a bare marker of the same character at least as long closes):
  - `plan_tasks FILE` → `N<TAB>title` per task heading (`^#+[ \t]+Task[ \t]+[0-9]+` outside fences).
  - `ledger_done FILE` → task numbers with a `Task N: complete` line, sorted, unique.
  - `plan_header_line FILE LABEL` → first unfenced line beginning `**LABEL:**`, or nothing.
  - `plan_header FILE` → every line before the first task heading.
  - `plan_task_text FILE N` → task N's heading through the line before the next task heading; exit 3 if absent.
  - `plan_apply_amendments PLAN AMEND` → the amended plan; the plan unchanged when AMEND is missing or empty; exit 1 with `amendment A<k> does not apply` on stderr.
  - `plan_amendments_file PLAN` → `<workspace>/amendments.md` when PLAN is in a git repository and the file is non-empty, else nothing.
  - `$_PLAN_AWK` → awk functions `in_fence(line)` (1 for fence markers and fenced lines) and `is_task(line)` (task number or -1); callers prepend it to their awk program.
- **`amendments.md` entry** (`<workspace>/amendments.md`, append-only): heading `## A<k> — Task <N>` or `## A<k> — Header` (`—` or `-`), then `Reason: …`, `Cost if wrong: …`, `### Old` and `### New`, each followed by a fence of 4 or more backticks. Old is whole lines matching the target exactly once; Old may not include `**Spec:**`, `**Execution:**`, `**Program:**`, `**Plan review:**`, `Host:` or `Routing policy:` lines.
- **`P/scripts/task-brief`**: `task-brief PLAN_FILE N [OUTFILE]` writes the amended task text plus `## Plan header excerpt` (the header's `## Global Constraints` and `## Contracts` sections); `task-brief --header PLAN_FILE [OUTFILE]` writes the amended header (default `<workspace>/plan-header.md`). First output line `wrote <path>: <N> lines`, last line the budget line. Exit 0 ok, 2 usage, 3 no such task, 4 amendment does not apply.
- **`P/scripts/plan-lint`**: `plan-lint PLAN_FILE [--amendments FILE]` prints `ERROR|WARN <header|Task N>: <what>` lines, then `plan-lint: <E> errors, <W> warnings`. Exit 0 no errors, 1 errors, 2 usage.
- **`P/scripts/plan-amend`**: `plan-amend PLAN_FILE BLOCK_FILE` (BLOCK_FILE heading `## A? — Task N`, `## Task N`, `## A? — Header` or `## Header`) prints `amended: A<k> <Task N|Header>` (exit 0) or `rejected: <reason>` (exit 1); exit 2 usage.
- **Ruling-seat verdict block**: `### Item <id>` / `Verdict: CONFIRMED-GAP | PARK | AMEND | BLOCKED` / `Ruling: <what> — <why> — <cost if wrong>`, then an amendment entry (AMEND) or `Decision needed: …` (BLOCKED). Item kinds: `preflight`, `plan-conflict`, `cannot-verify`, `risk3-spread`, `breaker`, `blocked-plan`, `codex-empty-diff`, `final-residual`.
- **New ledger lines**: `Task <N>: BLOCKED — ruling seat — <decision>`; `Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>`; `Ruling: amendment A<k> (Header) — <reason> — <cost if wrong>`; `Ruling: pre-flight — <clean | K findings, see preflight.md> — none`.
- **Plan review line**: `**Plan review:** <YYYY-MM-DD> — <judge agent> — executability e / coherence c / coverage v / assumptions a (round r)`. Criteria ids: `executability`, `coherence`, `coverage`, `assumptions`.
- **Process line**: `Process: <spike|bounded|architectural>, <inline|subagent> — <trigger | no trigger>`.

## Assumptions (evidence)

- Every script and test in Tasks 1–4 and the files in Tasks 5 and 10 were prototyped in the planning session on 2026-09-12 and passed: plan-lib 26/26, plan-lint 49/49, plan-amend 20/20, budget-line with the new checks 24/24, criteria 33/33, hook 33/33; the unchanged next-step (63), repo-audit (19) and snapshot (27) suites passed against the new library.
- `TMPDIR=/tmp` in Claude Code's Bash tool breaks git-backed suites; with `TMPDIR` in Windows form the unchanged `budget-line.test.sh` passes 8/8 (observed 2026-09-12).
- Plan review: Fable round 1 (17/14/16/17, 3 Important) and round 2 (17/17/16/17, 1 Important: the writing-plans template carried a placeholder Plan review line) were both fixed in full; round 2's fixes were machine-checked (quoted edits, lint, prototype suites) but not re-reviewed by a third round.
- `plan_amendments_file` returns the path only for a non-empty file where spec §3.1 says "exists": an empty file amends nothing, so the difference is harmless.
- Baselines for expected counts, 2026-09-12: `P/tests/hook.test.sh` reports `32 passed` (Task 10 adds the 33rd check); `grep -c plan-lint P/skills/writing-plans/references/assigning-implementers.md` is `0` (Task 9 expects `3`); `grep -c codex-empty-diff P/reference/external-executor.md` is `0` (Task 8 expects `2`).
- `awk` is GNU Awk 5.3.2 under Git Bash (`awk --version`, 2026-09-12).
- `impl-opus-high` is in both the `assignment` and `reserve` blocks: `P/reference/ladder.md:71` and `:133`.
- The literal-prefix check: `scripts/validate-repository.mjs:85-97`. The CommonMark fence rule reused: `scripts/validate-repository.mjs:66-74`.
- Judges are read-only (`tools: Read, Grep, Glob, WebFetch`): `P/agents/judge-fable.md:6`. `tests/fleet.test.sh` does not check `description:` (no match for `description`, 2026-09-12).
- `sdd-workspace` creates the workspace directory as a side effect: `P/scripts/sdd-workspace:35-40`.
- The handoff skill commits plan and spec and runs `next-step`: `P/skills/handoff/SKILL.md:39-69`.
- Only historical docs reference `plan-document-reviewer-prompt.md` (grep, 2026-09-12); deleting it breaks no link.
- No `**Executor:**` lines: the Codex executor lane fails on this Windows box (`jq: Argument list too long`, parked since sub-project 2) and the Codex quota is exhausted until 2026-09-16.
- Implementer lines use `dcc-superpower-companions:` names because dr-superpowers is not enabled on this machine; dr-superpowers' subagent-driven-development translates them through `reference/legacy-names.md`.
- `tests/ui-discovery.test.mjs` fails with `bash: rg: command not found` on this box; that failure is environmental and pre-existing.

## Task index

1. Shared plan library
2. task-brief: header excerpt, --header, amendments
3. plan-lint
4. plan-amend
5. Plan review criteria and prompt
6. Ruling-seat prompt and judge descriptions
7. subagent-driven-development: the ruling seat
8. Execution references route judgment to the seat
9. writing-plans: header, lint, review, handoff
10. Entry point and brainstorming alignment
11. Reinforcement blocks
12. README, version 1.4.0, full verification

---

### Task 1: Shared plan library

**Files:**
- Modify: `P/scripts/lib/plan.sh` (full replacement)
- Modify: `P/scripts/next-step:57-66`
- Test: `P/tests/plan-lib.test.sh` (full replacement)

**Interfaces:**
- Consumes: nothing.
- Produces: every `lib/plan.sh` function listed in Contracts, and `$_PLAN_AWK`.

**Implementer:** dcc-superpower-companions:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

The new fence rule changes `plan_tasks`, which `next-step`, `repo-audit` and the compaction snapshot share. Their suites must pass unchanged.

- [ ] **Step 1: Write the failing test**

Replace the whole of `P/tests/plan-lib.test.sh` with:

`````bash
#!/usr/bin/env bash
# lib/plan.sh is the one plan parser every script shares, so all of them agree
# on what a task, the header and an amendment are: fences by the CommonMark
# rule, CRLF tolerated.
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

# --- plan_tasks and ledger_done ---
printf '# Plan\n\n### Task 1: First thing\n\n```bash\n### Task 9: fenced\n```\n\n## Task 2 - Second\n\n### Task 10: Tenth\n' > "$TMP/plan.md"
check "plan_tasks: numbers outside fences" "$(plan_tasks "$TMP/plan.md" | cut -f1 | tr '\n' ' ')" "1 2 10 "
check "plan_tasks: titles" "$(plan_tasks "$TMP/plan.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
sed 's/$/\r/' "$TMP/plan.md" > "$TMP/crlf.md"
check "plan_tasks: CRLF" "$(plan_tasks "$TMP/crlf.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
printf '# Empty\n' > "$TMP/none.md"
check "plan_tasks: no tasks prints nothing" "$(plan_tasks "$TMP/none.md")" ""
printf '# P\n\n### Task 1: One\n\n````markdown\n```bash\necho hi\n```\n### Task 9: inside\n````\n\n~~~\n### Task 8: tilde\n~~~\n\n### Task 2: Two\n' > "$TMP/nested.md"
check "plan_tasks: a 4-backtick fence holds 3-backtick fences" "$(plan_tasks "$TMP/nested.md" | cut -f1 | tr '\n' ' ')" "1 2 "

printf '# SDD ledger — plan: x\nTask 2: complete (a)\nTask 1: fix round 1/5 (x)\nTask 1: complete (b)\nTask 2: complete (again)\nGroup 1-2: review round 1/5\n' > "$TMP/ledger.md"
check "ledger_done: unique and sorted" "$(ledger_done "$TMP/ledger.md" | tr '\n' ' ')" "1 2 "
sed 's/$/\r/' "$TMP/ledger.md" > "$TMP/ledger-crlf.md"
check "ledger_done: CRLF" "$(ledger_done "$TMP/ledger-crlf.md" | tr '\n' ' ')" "1 2 "
printf '# SDD ledger — plan: x\nTask 3: fix round 1/5 (x)\n' > "$TMP/open.md"
check "ledger_done: nothing complete" "$(ledger_done "$TMP/open.md")" ""

# --- header, header lines and task text ---
printf '# P\n\n**Spec:** `a.md`\n\n```\n**Execution:** fenced\n```\n**Execution:** subagent — x\n\n## Global Constraints\n\n- c\n\n### Task 1: One\n\nbody 1\n\n### Task 2: Two\n\nbody 2\n' > "$TMP/h.md"
check "plan_header_line: first unfenced match" "$(plan_header_line "$TMP/h.md" Execution)" "**Execution:** subagent — x"
check "plan_header_line: no match prints nothing" "$(plan_header_line "$TMP/h.md" Program)" ""
check "plan_header: stops before the first task" "$(plan_header "$TMP/h.md" | tail -n 2 | head -n 1)" "- c"
check "plan_task_text: heading to the next task" "$(plan_task_text "$TMP/h.md" 1 | tr '\n' '|')" "### Task 1: One||body 1||"
check "plan_task_text: last task runs to the end" "$(plan_task_text "$TMP/h.md" 2 | tr '\n' '|')" "### Task 2: Two||body 2|"
plan_task_text "$TMP/h.md" 7 > /dev/null
check "plan_task_text: absent task exits 3" "$?" "3"
sed 's/$/\r/' "$TMP/h.md" > "$TMP/hc.md"
check "plan_task_text: CRLF" "$(plan_task_text "$TMP/hc.md" 2 | tr '\n' '|')" "### Task 2: Two||body 2|"

# --- plan_apply_amendments ---
cat > "$TMP/am.md" <<'EOF'
## A1 — Task 2
Reason: r
Cost if wrong: c
### Old
````text
body 2
````
### New
````text
body 2 amended
```bash
echo fenced
```
````

## A2 - Header
Reason: r
Cost if wrong: c
### Old
````text
- c
````
### New
````text
````
EOF
out=$(plan_apply_amendments "$TMP/h.md" "$TMP/am.md"); status=$?
check "apply: exit 0" "$status" "0"
check "apply: task target, fenced New kept" "$(printf '%s\n' "$out" | tail -n 4 | tr '\n' '|')" 'body 2 amended|```bash|echo fenced|```|'
check "apply: header target, empty New deletes" "$(printf '%s\n' "$out" | grep -c '^- c$')" "0"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nbody 2\n````\n### New\n````text\nx\n````\n' > "$TMP/bad.md"
plan_apply_amendments "$TMP/h.md" "$TMP/bad.md" > /dev/null 2> "$TMP/err"
check "apply: old text outside its target exits 1" "$?" "1"
check "apply: names the entry" "$(cat "$TMP/err")" "amendment A1 does not apply"
printf '# P\n\n### Task 1: One\n\nx\nx\n' > "$TMP/dup.md"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nx\n````\n### New\n````text\ny\n````\n' > "$TMP/dup-am.md"
plan_apply_amendments "$TMP/dup.md" "$TMP/dup-am.md" > /dev/null 2>&1
check "apply: old text twice exits 1" "$?" "1"
printf '# P\n\n### Task 1: One\n\n```bash\nold line\nsecond\n```\n' > "$TMP/multi.md"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nold line\nsecond\n````\n### New\n````text\nnew line\n````\n' > "$TMP/multi-am.md"
check "apply: multi-line old text inside a fence" "$(plan_apply_amendments "$TMP/multi.md" "$TMP/multi-am.md" | tail -n 2 | tr '\n' '|')" 'new line|```|'
check "apply: missing amendments file prints the plan" \
  "$(plan_apply_amendments "$TMP/h.md" "$TMP/no-such.md" | wc -l | tr -d ' ')" "$(wc -l < "$TMP/h.md" | tr -d ' ')"

# --- plan_amendments_file ---
export GIT_CONFIG_NOSYSTEM=1
REPO="$TMP/repo"
git init -q "$REPO"
cp "$TMP/h.md" "$REPO/plan.md"
check "amendments_file: none yet" "$(plan_amendments_file "$REPO/plan.md")" ""
mkdir -p "$REPO/.superpowers/sdd/plan"
cp "$TMP/am.md" "$REPO/.superpowers/sdd/plan/amendments.md"
got=$(plan_amendments_file "$REPO/plan.md")
check "amendments_file: the plan's workspace file" "${got##*/.superpowers/}" "sdd/plan/amendments.md"
check "amendments_file: outside a repository" "$(plan_amendments_file "$TMP/h.md")" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
`````

- [ ] **Step 2: Run it to verify it fails**

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 120 bash plugins/dr-superpowers/tests/plan-lib.test.sh`
Expected: FAIL lines for the new checks (for example `plan_header_line: command not found`, and the 4-backtick fence check reporting `1 9 2 ` or similar), and a summary with failures.

- [ ] **Step 3: Replace the library**

Replace the whole of `P/scripts/lib/plan.sh` with:

`````bash
# Plan and ledger parsing shared by task-brief, plan-lint, plan-amend, next-step
# and repo-audit, so every reader agrees on what a task, the header and an
# amendment are. Sourced; defines functions only.

_PLAN_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# CommonMark fence rule, the one scripts/validate-repository.mjs uses: a fence
# closes only at a bare marker of the same character at least as long as the
# opener, so a 4-backtick block may hold 3-backtick fences. in_fence(line)
# returns 1 for fence markers and fenced lines. is_task(line) returns the task
# number of a task heading, or -1.
_PLAN_AWK='
function in_fence(line,   t, mk) {
  if (FENCE != "") {
    t = line; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
    if (t ~ /^(`+|~+)$/ && substr(t, 1, 1) == substr(FENCE, 1, 1) && length(t) >= length(FENCE)) FENCE = ""
    return 1
  }
  if (match(line, /^ ? ? ?(`+|~+)/)) {
    mk = substr(line, RSTART, RLENGTH); sub(/^ +/, "", mk)
    if (length(mk) >= 3) { FENCE = mk; return 1 }
  }
  return 0
}
function is_task(line,   n) {
  if (line !~ /^#+[ \t]+Task[ \t]+[0-9]+/) return -1
  n = line; sub(/^#+[ \t]+Task[ \t]+/, "", n); sub(/[^0-9].*$/, "", n)
  return n + 0
}
'

# plan_tasks FILE — one "N<TAB>title" line per task heading outside fences.
plan_tasks() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
    in_fence($0) { next }
    is_task($0) >= 0 {
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

# plan_header_line FILE LABEL — the first line outside fences that begins
# "**LABEL:**", or nothing.
plan_header_line() {
  tr -d '\r' < "$1" | awk -v p="**$2:**" "$_PLAN_AWK"'
    in_fence($0) { next }
    index($0, p) == 1 { print; exit }
  '
}

# plan_header FILE — every line before the first task heading.
plan_header() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
    { f = in_fence($0) }
    !f && is_task($0) >= 0 { exit }
    { print }
  '
}

# plan_task_text FILE N — task N from its heading to the line before the next
# task heading. Exit 3 when there is no such task.
plan_task_text() {
  tr -d '\r' < "$1" | awk -v want="$2" "$_PLAN_AWK"'
    { f = in_fence($0); k = f ? -1 : is_task($0) }
    k >= 0 { intask = (k == want + 0); if (intask) found = 1 }
    intask { print }
    END { exit found ? 0 : 3 }
  '
}

# plan_apply_amendments PLAN AMEND — the plan with every amendments.md entry
# applied in file order; the plan unchanged when AMEND is missing or empty.
# Exit 1, naming the entry on stderr, when an entry does not apply: its Old
# lines must match a contiguous run of whole lines of its target exactly once.
plan_apply_amendments() {
  if [ ! -s "${2:-}" ]; then tr -d '\r' < "$1"; return 0; fi
  awk "$_PLAN_AWK"'
    function close_marker(t, open) {
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      return t ~ /^(`+|~+)$/ && substr(t, 1, 1) == substr(open, 1, 1) && length(t) >= length(open)
    }
    function bounds(ent,   i, k) {
      FENCE = ""; S = 0; E = 0
      for (i = 1; i <= n; i++) {
        k = in_fence(L[i]) ? -1 : is_task(L[i])
        if (TGT[ent] == "H") { if (k >= 0) { S = 1; E = i - 1; return } }
        else if (S == 0 && k == TGT[ent] + 0) S = i
        else if (S > 0 && k >= 0) { E = i - 1; return }
      }
      if (TGT[ent] == "H") { S = 1; E = n } else if (S > 0) E = n
    }
    FNR == NR {
      sub(/\r$/, "")
      if (mode != "" ) {
        if (close_marker($0, open)) { mode = ""; next }
        if (mode == "old") OLD[m, ++OC[m]] = $0; else NEW[m, ++NC[m]] = $0
        next
      }
      if ($0 ~ /^## A[0-9]+ (—|-) (Task [0-9]+|Header)[ \t]*$/) {
        m++; ID[m] = $2
        t = $0; sub(/^## A[0-9]+ (—|-) /, "", t); sub(/[ \t]+$/, "", t)
        if (t == "Header") TGT[m] = "H"; else { sub(/^Task /, "", t); TGT[m] = t }
        sect = ""; next
      }
      if ($0 ~ /^### Old[ \t]*$/) { sect = "old"; next }
      if ($0 ~ /^### New[ \t]*$/) { sect = "new"; next }
      if (sect != "" && match($0, /^(````+|~~~~+)/)) {
        open = substr($0, RSTART, RLENGTH); mode = sect; sect = ""; next
      }
      next
    }
    { sub(/\r$/, ""); L[++n] = $0 }
    END {
      for (e = 1; e <= m; e++) {
        bounds(e)
        k = OC[e] + 0; hits = 0
        if (S > 0 && k > 0)
          for (i = S; i + k - 1 <= E; i++) {
            ok = 1
            for (j = 1; j <= k; j++) if (L[i + j - 1] != OLD[e, j]) { ok = 0; break }
            if (ok) { hits++; at = i }
          }
        if (hits != 1) { print "amendment " ID[e] " does not apply" > "/dev/stderr"; exit 1 }
        c = 0
        for (i = 1; i < at; i++) N2[++c] = L[i]
        for (j = 1; j <= NC[e] + 0; j++) N2[++c] = NEW[e, j]
        for (i = at + k; i <= n; i++) N2[++c] = L[i]
        delete L; n = c
        for (i = 1; i <= n; i++) L[i] = N2[i]
        delete N2
      }
      for (i = 1; i <= n; i++) print L[i]
    }
  ' "$2" "$1"
}

# plan_amendments_file PLAN — <workspace>/amendments.md when PLAN is inside a
# git repository and that file is non-empty; otherwise nothing.
plan_amendments_file() {
  local dir
  dir=$(cd "$(dirname "$1")" 2>/dev/null \
    && git rev-parse --show-toplevel >/dev/null 2>&1 \
    && "$_PLAN_LIB_DIR/../sdd-workspace" "$(basename "$1")" 2>/dev/null) || return 0
  [ -s "$dir/amendments.md" ] && printf '%s\n' "$dir/amendments.md"
  return 0
}
`````

- [ ] **Step 4: Point next-step at the library**

In `P/scripts/next-step`, replace these five lines:

````text
  header_line() { # first unfenced line starting with **<label>:**
    awk -v p="^\\\\*\\\\*$1:\\\\*\\\\*" '/^```/ { f = !f } !f && $0 ~ p { print; exit }' <<<"$plan_text"
  }
  execution=$(header_line Execution)
  program=$(header_line Program)
````

with:

````text
  execution=$(plan_header_line "$plan" Execution)
  program=$(plan_header_line "$plan" Program)
````

Then delete the line, a few lines above, that only the removed helper used:

````text
  plan_text=$(tr -d '\r' < "$plan")
````

Leave the rest of `next-step` unchanged; it already sources `lib/plan.sh`.

- [ ] **Step 5: Run the library and its consumers' suites**

Run:

```bash
export TMPDIR="$(cygpath -m "$TMP")"
for t in plan-lib next-step repo-audit snapshot; do
  timeout 120 bash "plugins/dr-superpowers/tests/$t.test.sh" | tail -n 1
done
```

Expected, in order: `26 passed, 0 failed`, `63 passed, 0 failed`, `19 passed, 0 failed`, `27 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/scripts/next-step plugins/dr-superpowers/tests/plan-lib.test.sh
git commit -m "refactor(superpowers): share header and amendment parsing"
```

---

### Task 2: task-brief: header excerpt, --header, amendments

**Files:**
- Modify: `P/scripts/task-brief` (full replacement)
- Test: `P/tests/budget-line.test.sh` (insert a block)

**Interfaces:**
- Consumes: `plan_apply_amendments`, `plan_amendments_file`, `plan_header`, `plan_task_text` from Task 1.
- Produces: the `task-brief` contract in Contracts (both modes, exit 4).

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

Every dispatch reads a brief, so the first output line, the last (budget) line and exit codes 0/2/3 must not change.

- [ ] **Step 1: Write the failing tests**

In `P/tests/budget-line.test.sh`, insert this block immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

`````bash
# --- header excerpt, --header, amendments ---
cat > docs/full.md <<'EOF'
# Plan

**Execution:** subagent — `claude --model sonnet --effort high` — x

## Global Constraints

- Bash only.

## Contracts

- `greet NAME` prints `hello NAME`.

## Task index

1. One

### Task 1: One

Print `hello NAME`.
EOF
out=$(bash "$P/scripts/task-brief" docs/full.md 1 "$TMP/b1.md" 2>/dev/null); status=$?
check "task-brief: explicit OUTFILE exit 0" "$status" "0"
check "task-brief: brief carries the excerpt heading" "$(grep -c '^## Plan header excerpt$' "$TMP/b1.md")" "1"
check "task-brief: excerpt carries Global Constraints" "$(grep -c '^- Bash only.$' "$TMP/b1.md")" "1"
check "task-brief: brief ends with Contracts" "$(tail -n 1 "$TMP/b1.md")" '- `greet NAME` prints `hello NAME`.'
check "task-brief: excerpt carries Contracts" "$(grep -c '^- `greet NAME` prints `hello NAME`.$' "$TMP/b1.md")" "1"
check "task-brief: excerpt omits Task index" "$(grep -c '^## Task index$' "$TMP/b1.md")" "0"
out=$(bash "$P/scripts/task-brief" --header docs/full.md 2>/dev/null); status=$?
check "task-brief --header: exit 0" "$status" "0"
check "task-brief --header: default path" "$(sed -n 1p <<<"$out" | grep -c 'plan-header.md: ')" "1"
check "task-brief --header: stops before Task 1" "$(tail -n 1 "$REPO/.superpowers/sdd/full/plan-header.md")" ""
check "task-brief --header: carries Task index" "$(grep -c '^## Task index$' "$REPO/.superpowers/sdd/full/plan-header.md")" "1"
mkdir -p "$REPO/.superpowers/sdd/full"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nPrint `hello NAME`.\n````\n### New\n````text\nPrint `hi NAME`.\n````\n\n## A2 — Header\nReason: r\nCost if wrong: c\n### Old\n````text\n- Bash only.\n````\n### New\n````text\n- Bash 4 or later.\n````\n' \
  > "$REPO/.superpowers/sdd/full/amendments.md"
bash "$P/scripts/task-brief" docs/full.md 1 "$TMP/b2.md" >/dev/null 2>&1
check "task-brief: amendment applied to the task, explicit OUTFILE" "$(grep -c '^Print `hi NAME`.$' "$TMP/b2.md")" "1"
check "task-brief: amendment applied to the excerpt" "$(grep -c '^- Bash 4 or later.$' "$TMP/b2.md")" "1"
bash "$P/scripts/task-brief" --header docs/full.md >/dev/null 2>&1
check "task-brief --header: amendment applied" "$(grep -c '^- Bash 4 or later.$' "$REPO/.superpowers/sdd/full/plan-header.md")" "1"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nnot there\n````\n### New\n````text\nx\n````\n' \
  > "$REPO/.superpowers/sdd/full/amendments.md"
err=$(bash "$P/scripts/task-brief" docs/full.md 1 "$TMP/b3.md" 2>&1 >/dev/null); status=$?
check "task-brief: non-applying amendment exits 4" "$status" "4"
check "task-brief: names the amendment" "$err" "amendment A1 does not apply"
bash "$P/scripts/task-brief" --header >/dev/null 2>&1; status=$?
check "task-brief --header without a plan: exit 2" "$status" "2"
`````

- [ ] **Step 2: Run it to verify it fails**

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 120 bash plugins/dr-superpowers/tests/budget-line.test.sh`
Expected: the 8 existing checks pass; the new checks FAIL (no `## Plan header excerpt`, `--header` treated as a plan path, amendments ignored), except the last one — `--header` without a plan already exits 2.

- [ ] **Step 3: Replace task-brief**

Replace the whole of `P/scripts/task-brief` with:

`````bash
#!/usr/bin/env bash
# Extract one task's full text from an implementation plan into a file the
# implementer reads in one call, so the task text never has to be pasted
# through the controller's context. The brief ends with the plan header's
# Global Constraints and Contracts, so every reader of the brief sees the
# cross-task names it uses. --header writes the whole header instead.
# Amendments in <workspace>/amendments.md are applied first.
#
# Usage: task-brief PLAN_FILE TASK_NUMBER [OUTFILE]
#        task-brief --header PLAN_FILE [OUTFILE]
# Default OUTFILE: <repo-root>/.superpowers/sdd/<plan-basename>/task-<N>-brief.md
# or .../plan-header.md (per plan and per worktree; concurrent runs of the SAME
# plan in the same working tree share it).
# Exit: 0 ok; 2 usage; 3 no such task; 4 an amendment does not apply.
# Last output line: the session budget line from scripts/context-size.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"

header=0
if [ "${1:-}" = "--header" ]; then header=1; shift; fi
if { [ "$header" -eq 1 ] && { [ $# -lt 1 ] || [ $# -gt 2 ]; }; } \
   || { [ "$header" -eq 0 ] && { [ $# -lt 2 ] || [ $# -gt 3 ]; }; }; then
  echo "usage: task-brief PLAN_FILE TASK_NUMBER [OUTFILE] | task-brief --header PLAN_FILE [OUTFILE]" >&2
  exit 2
fi

plan=$1
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
if [ "$header" -eq 1 ]; then n="" given=${2:-}; else n=$2 given=${3:-}; fi

if [ -n "$given" ]; then
  out=$given
else
  dir=$("$HERE/sdd-workspace" "$plan")
  if [ "$header" -eq 1 ]; then out="$dir/plan-header.md"; else out="$dir/task-${n}-brief.md"; fi
fi

src=$(mktemp)
trap 'rm -f "$src" "$src.err"' EXIT
if ! plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")" > "$src" 2> "$src.err"; then
  cat "$src.err" >&2
  exit 4
fi

if [ "$header" -eq 1 ]; then
  plan_header "$src" > "$out"
else
  if ! plan_task_text "$src" "$n" > "$out"; then
    echo "task ${n} not found in ${plan} (no heading matching 'Task ${n}')" >&2
    exit 3
  fi
  excerpt=$(plan_header "$src" | awk '/^## / { on = ($0 == "## Global Constraints" || $0 == "## Contracts") } on { print }')
  if [ -n "$excerpt" ]; then
    printf '\n## Plan header excerpt\n\n%s\n' "$excerpt" >> "$out"
  fi
fi

echo "wrote ${out}: $(wc -l < "$out" | tr -d ' ') lines"

# The budget line rides on a call the controller already makes before every
# task, so checking the session budget costs no extra request. It must never
# fail the brief.
"$HERE/context-size" 2>/dev/null || true
`````

- [ ] **Step 4: Run the suites that call task-brief**

Run:

```bash
export TMPDIR="$(cygpath -m "$TMP")"
for t in budget-line plan-lib; do
  timeout 120 bash "plugins/dr-superpowers/tests/$t.test.sh" | tail -n 1
done
```

Expected: `24 passed, 0 failed`, then `26 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/tests/budget-line.test.sh
git commit -m "feat(superpowers): carry header excerpt in briefs"
```

---

### Task 3: plan-lint

**Files:**
- Create: `P/scripts/plan-lint`
- Test: `P/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: `$_PLAN_AWK`, `plan_tasks`, `plan_header`, `plan_header_line`, `plan_task_text`, `plan_apply_amendments`, `plan_amendments_file` from Task 1; the fenced `assignment`, `reserve`, `gate` and `codex-assignment` blocks of `P/reference/ladder.md`; `P/reference/codex-routing.json`.
- Produces: the `plan-lint` contract in Contracts; Task 4 compares its ERROR lines.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

Reserve names are the `reserve` block's first-column tokens that are neither `BLOCKED` nor in the `assignment` block, so `impl-opus-high` (in both) is legal at total 6. Implementer prefixes are resolved by suffix; plan-lint never spells an old prefix.

- [ ] **Step 1: Write the failing test**

Create `P/tests/plan-lint.test.sh`:

`````bash
#!/usr/bin/env bash
# plan-lint is the one mechanical checker for plan shape; each fixture below
# pins one finding class so a planner of any size gets the same verdict.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/../scripts/plan-lint"

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
cd "$TMP"
mkdir -p docs
printf '# Spec\n' > docs/spec.md
printf '# Program\n' > docs/program.md

claude_plan() {
  cat <<'EOF'
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4

**Program:** `docs/program.md` — sub-project 1 of 2 — next: Second part

**Plan review:** 2026-09-12 — dr-superpowers:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. First thing
2. Second thing

### Task 1: First thing

**Files:**
- Create: `a.txt`

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Write it**

```bash
# a fenced TODO is only a warning
echo hi
```

### Task 2: Second thing

**Files:**
- Modify: `a.txt`

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
**Approach:** inline - skip 2: follows the pattern

- [ ] **Step 1: Mark the `TODO` column**
EOF
}

codex_plan() {
  cat <<'EOF'
# Codex Demo Plan

Host: codex
Routing policy: codex-v2

**Goal:** Demo.

**Spec:** docs/spec.md

**Execution:** subagent — codex gpt-5.6-sol / high — native pair

**Plan review:** 2026-09-12 — codex gpt-6-astra / high — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- None.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. One

### Task 1: One

**Files:**
- Create: `b.txt`

**Implementer:** codex gpt-5.6-terra / medium
**Evaluation:** files=1, spec=1, coupling=1, risk=0; weighted routing score=3
**Assignment source:** rubric
EOF
}

lint() { # lint <file> [args...]; sets out and status
  out=$(bash "$LINT" "$@" 2>&1); status=$?
}
variant() { # variant <name> <sed expression> — the Claude plan with one edit
  claude_plan | sed -E "$2" > "$1"
}

# --- clean plans ---
claude_plan > clean.md
lint clean.md
check "clean Claude plan: exit 0" "$status" "0"
has "clean Claude plan: summary" "$out" "plan-lint: 0 errors, 1 warnings"
has "fenced TODO is a warning" "$out" "WARN Task 1: placeholder: # a fenced TODO is only a warning"
lacks "inline-code TODO is not a finding" "$out" "Mark the"
codex_plan > codex.md
lint codex.md
check "clean Codex plan: exit 0" "$status" "0"
check "clean Codex plan: summary" "$out" "plan-lint: 0 errors, 0 warnings"

# --- usage ---
lint nope.md
check "missing file: exit 2" "$status" "2"
lint clean.md --bogus x
check "bad flag: exit 2" "$status" "2"

# --- header ---
variant v1.md '/^## Contracts$/d'
lint v1.md
check "missing section: exit 1" "$status" "1"
has "missing section: named" "$out" "ERROR header: missing '## Contracts' section"
variant v2.md 's#`docs/spec.md`#`docs/nope.md`#'
lint v2.md
has "missing Spec path" "$out" "ERROR header: Spec path does not exist: docs/nope.md"
variant v3.md 's/^2\. Second thing$/2. Second/'
lint v3.md
has "index mismatch" "$out" "ERROR header: Task index does not match the task headings"
variant v4.md 's/^### Task 2: Second thing$/### Second thing (Task 2)/'
lint v4.md
has "malformed heading (Task N) suffix" "$out" "ERROR header: malformed task heading: ### Second thing (Task 2)"
variant v5.md 's/^### Task 2: Second thing$/### task 2: Second thing/'
lint v5.md
has "malformed heading lowercase" "$out" "ERROR header: malformed task heading: ### task 2: Second thing"
variant v6.md 's/^- \[ \] \*\*Step 1: Write it\*\*$/#### Step 1: Run Task 2 tests/'
lint v6.md
lacks "a step heading mentioning a task is not a finding" "$out" "malformed task heading"
variant v7.md 's/^### Task 2: Second thing$/### Task 3: Second thing/; s/^2\. Second thing$/3. Second thing/'
lint v7.md
has "non-contiguous numbers" "$out" "ERROR header: task numbers must run 1..N in order: found Task 3 at position 2"
variant v8.md 's/^\*\*Execution:\*\* .*/**Execution:** subagent — `claude --model gpt --effort high` — x/'
lint v8.md
has "Execution grammar" "$out" "ERROR header: Execution line does not match"
variant v9.md 's/^\*\*Execution:\*\* .*/**Execution:** inline -- claude --model sonnet --effort medium -- all small/'
lint v9.md
has "inline breaks R5" "$out" "ERROR header: inline execution needs every task at total <= 3 and risk < 3; fails on Task 2"
lacks "double-hyphen separators and bare command parse" "$out" "Execution line does not match"
variant v10.md 's/^\*\*Program:\*\* .*/**Program:** `docs\/program.md` — sub-project 3 of 2 — last/'
lint v10.md
has "Program k > n" "$out" "ERROR header: Program line: sub-project 3 of 2"
variant v11.md 's/^- Bash only\.$/- Error handling is TBD./'
lint v11.md
has "prose TBD is an error" "$out" "ERROR header: placeholder: - Error handling is TBD."
variant v12.md 's/^- Bash only\.$/- Similar to Task 1./'
lint v12.md
has "similar to Task N" "$out" "ERROR header: placeholder: - Similar to Task 1."
variant v13.md 's/^- Bash only\.$/- Handle edge cases./'
lint v13.md
check "soft placeholder only warns: exit 0" "$status" "0"
has "soft placeholder" "$out" "WARN header: placeholder: - Handle edge cases."
variant v14.md '/^\*\*Plan review:\*\*/d'
lint v14.md
has "missing plan review warns" "$out" "WARN header: no **Plan review:** line yet"

# --- per task, Claude ---
variant t1.md 's/risk 2 = 4/risk 2 = 5/'
lint t1.md
has "sum mismatch" "$out" "ERROR Task 2: scores sum to 4, not 5"
variant t2.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 1 - coupling 1 - risk 0 = 4/'
lint t2.md
has "Rule S" "$out" "ERROR Task 2: Rule S: files+spec+coupling must be below 4 and spec below 3"
variant t3.md 's/impl-opus-low$/impl-opus-medium/'
lint t3.md
has "wrong agent" "$out" "ERROR Task 2: Implementer impl-opus-medium does not match the assignment table's impl-opus-low for total 4"
variant t4.md 's/impl-opus-low$/impl-fable-high/'
lint t4.md
has "reserve name" "$out" "ERROR Task 2: impl-fable-high is a reserve tier; it needs a human **Override:**"
variant t5.md 's/impl-opus-low$/impl-fable-high/; s/^(\*\*Approach:\*\* .*)$/\1\n**Override:** owner wants Fable here/'
lint t5.md
check "Override downgrades: exit 0" "$status" "0"
has "Override downgrades to WARN" "$out" "WARN Task 2: impl-fable-high is a reserve tier"
variant t6.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 3 = 6/; s/impl-opus-low$/impl-opus-high/'
lint t6.md
lacks "impl-opus-high at total 6 is not a reserve finding" "$out" "reserve tier"
lacks "impl-opus-high at total 6 matches" "$out" "does not match the assignment"
variant t7.md "s/^(\*\*Implementer:\*\*) dr-superpowers:impl-sonnet-low$/\1 old-$(printf 'plug'):impl-sonnet-low/"
lint t7.md
has "legacy prefix warns" "$out" "WARN Task 1: legacy prefix 'old-plug:'"
variant t8.md 's/^\*\*Approach:\*\* .*/**Approach:** inline - follows the pattern/'
lint t8.md
has "inline Approach needs skip" "$out" "ERROR Task 2: an inline Approach must cite 'skip <n>'"
variant t9.md 's/^\*\*Approach:\*\* .*/**Approach:** gut feeling/'
lint t9.md
has "Approach grammar" "$out" "ERROR Task 2: Approach does not match"
variant t10.md 's/^(\*\*Evaluation:\*\* files 0 - spec 0 - coupling 1 - risk 0 = 1)$/\1\n**Executor:** codex gpt-5.5 \/ medium/'
lint t10.md
has "Executor below the gate" "$out" "ERROR Task 1: total 1 / risk 0 fails the lane gate (min_score 2, max_risk 1)"
has "Executor without header line" "$out" "ERROR Task 1: Executor used but the header's '> **External executors:**' line does not name codex"
variant t11.md 's/^(\*\*Approach:\*\* .*)$/\1\n**Override:** kept\n**Executor:** codex gpt-5.6-sol \/ high/'
lint t11.md
has "Executor on an overridden task" "$out" "ERROR Task 2: an Executor line on an overridden task fails the lane gate"
variant t13.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 0 - coupling 0 - risk 4 = 4/'
lint t13.md
has "axis out of range" "$out" "ERROR Task 2: each axis must be 0-3"
variant t12.md '/^- Modify: `a.txt`$/d; s/^\*\*Files:\*\*$/Files:/'
lint t12.md
has "missing Files" "$out" "ERROR Task 2: missing **Files:** block"

# --- per task, Codex ---
codex_plan | sed 's/weighted routing score=3/weighted routing score=4/' > c1.md
lint c1.md
has "weighted score mismatch" "$out" "ERROR Task 1: weighted routing score 4 is not files+spec+coupling+2*risk = 3"
codex_plan | sed 's#gpt-5.6-terra / medium#gpt-5.6-terra / low#' > c2.md
lint c2.md
has "rank below score" "$out" "ERROR Task 1: Implementer rank 2 is below routing score 3"
codex_plan | sed 's#gpt-5.6-terra / medium#gpt-5.6-terra / high#' > c3.md
lint c3.md
check "promotion: exit 0" "$status" "0"
has "promotion warns" "$out" "WARN Task 1: Implementer rank 4 is above routing score 3 (promotion)"

# --- amendments ---
cat > am.md <<'EOF'
## A1 — Task 2
Reason: the plan picked the wrong tier
Cost if wrong: one re-dispatch
### Old
````text
**Implementer:** dr-superpowers:impl-opus-low
````
### New
````text
**Implementer:** dr-superpowers:impl-opus-medium
````
EOF
lint clean.md --amendments am.md
has "amendments applied before checks" "$out" "ERROR Task 2: Implementer impl-opus-medium does not match"
sed 's/impl-opus-low$/impl-haiku/' am.md > am-bad.md
lint clean.md --amendments am-bad.md
has "non-applying amendment" "$out" "ERROR header: amendment A1 does not apply"

# --- nested fences and CRLF ---
{ claude_plan; printf '\n````markdown\n```bash\necho x\n```\n### Task 9: inside a fixture\n````\n'; } > nested.md
lint nested.md
check "nested fence holds no task: exit 0" "$status" "0"
sed 's/$/\r/' clean.md > crlf.md
lint crlf.md
check "CRLF plan: exit 0" "$status" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
`````

- [ ] **Step 2: Run it to verify it fails**

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 120 bash plugins/dr-superpowers/tests/plan-lint.test.sh | tail -n 1`
Expected: a summary with failures (the script does not exist yet, so every `lint` call exits 127).

- [ ] **Step 3: Write plan-lint**

Create `P/scripts/plan-lint`:

`````bash
#!/usr/bin/env bash
# Check an implementation plan's shape mechanically, so a planner of any size
# gets the same verdict: the header block, task headings and index, the
# Execution line, placeholders, and every task's assignment lines against
# reference/ladder.md (Claude) or reference/codex-routing.json (Codex).
#
# Usage: plan-lint PLAN_FILE [--amendments FILE]
# Default amendments: <workspace>/amendments.md inside a git repository.
# Output: "ERROR|WARN <header|Task N>: <what>" lines, then a summary line.
# Exit: 0 no errors; 1 errors; 2 usage or missing file.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"
LADDER="$HERE/../reference/ladder.md"
ROUTING="$HERE/../reference/codex-routing.json"

usage() { echo "usage: plan-lint PLAN_FILE [--amendments FILE]" >&2; exit 2; }
[ $# -eq 1 ] || [ $# -eq 3 ] || usage
plan=$1
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
amend=""
if [ $# -eq 3 ]; then
  [ "$2" = "--amendments" ] || usage
  amend=$3
else
  amend=$(plan_amendments_file "$plan")
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
src="$TMP/plan.md"
findings="$TMP/findings"
: > "$findings"
say() { printf '%s %s: %s\n' "$1" "$2" "$3" >> "$findings"; } # say SEV WHERE WHAT

if ! plan_apply_amendments "$plan" "$amend" > "$src" 2> "$TMP/amend.err"; then
  say ERROR header "$(head -n 1 "$TMP/amend.err")"
  tr -d '\r' < "$plan" > "$src"
fi

root=$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null || pwd)
SEP='( — | – | - | -- )'
header=$(plan_header "$src")
block() { tr -d '\r' < "$LADDER" | awk -v b="$1" '$0 == "```" b { on = 1; next } on && /^```/ { exit } on { print }'; }

codex=0
grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$header" && codex=1

# --- header labels and sections ---
for label in Goal Spec Execution; do
  [ -n "$(plan_header_line "$src" "$label")" ] || say ERROR header "missing **$label:** line"
done
for section in "Global Constraints" "Contracts" "Assumptions (evidence)" "Task index"; do
  grep -qxF "## $section" <<<"$header" || say ERROR header "missing '## $section' section"
done
[ -n "$(plan_header_line "$src" 'Plan review')" ] || say WARN header "no **Plan review:** line yet"

spec_line=$(plan_header_line "$src" Spec)
if [ -n "$spec_line" ]; then
  spec_path=$(sed -E 's/^\*\*Spec:\*\*[ \t]*`?([^` \t]+)`?.*/\1/' <<<"$spec_line")
  [ -f "$root/$spec_path" ] || say ERROR header "Spec path does not exist: $spec_path"
fi

program=$(plan_header_line "$src" Program)
if [ -n "$program" ]; then
  if [[ "$program" =~ ^\*\*Program:\*\*\ \`?([^\`\ ]+)\`?$SEP"sub-project "([0-9]+)" of "([0-9]+)$SEP(next:\ .+|last)$ ]]; then
    ppath=${BASH_REMATCH[1]} k=${BASH_REMATCH[3]} n=${BASH_REMATCH[4]}
    [ "$k" -le "$n" ] || say ERROR header "Program line: sub-project $k of $n"
    [ -f "$root/$ppath" ] || say ERROR header "Program path does not exist: $ppath"
  else
    say ERROR header "Program line does not match '**Program:** <path> — sub-project <k> of <n> — next: <title>' or '… — last'"
  fi
fi

# --- task headings and index ---
tasks=$(plan_tasks "$src")
[ -n "$tasks" ] || say ERROR header "no task headings ('### Task N: <title>')"
nums=$(cut -f1 <<<"$tasks" | grep -v '^$' || true)
i=0
for n in $nums; do
  i=$((i + 1))
  [ "$n" -eq "$i" ] || { say ERROR header "task numbers must run 1..N in order: found Task $n at position $i"; break; }
done

awk "$_PLAN_AWK"'
  in_fence($0) { next }
  /^#+[ \t]+/ {
    t = $0; sub(/^#+[ \t]+/, "", t)
    if ((tolower(t) ~ /^task[^a-z]*[0-9]/ && t !~ /^Task[ \t]+[0-9]+/) || t ~ /\(Task [0-9]+\)[ \t]*$/)
      print "ERROR header: malformed task heading: " $0
  }
' "$src" >> "$findings"

index_lines=$(awk '$0 == "## Task index" { on = 1; next } on && /^## / { exit } on && /^[0-9]+\. / { print }' <<<"$header" \
  | sed -E 's/^([0-9]+)\. /\1\t/')
[ "$index_lines" = "$tasks" ] || say ERROR header "Task index does not match the task headings (numbers and titles, in order)"

# --- Execution line (R6) ---
execution=$(plan_header_line "$src" Execution)
mode=""
if [ -n "$execution" ]; then
  if [ "$codex" -eq 1 ]; then
    if [[ "$execution" =~ ^\*\*Execution:\*\*\ (inline|subagent)$SEP\`?codex\ ([a-z0-9.-]+)\ /\ ([a-z]+)\`?$SEP.+ ]]; then
      mode=${BASH_REMATCH[1]}
      m=${BASH_REMATCH[3]} e=${BASH_REMATCH[4]}
      jq -e --arg m "$m" --arg e "$e" '[.execution[], .reserve[]] | any(.model == $m and .effort == $e)' "$ROUTING" >/dev/null 2>&1 \
        || say ERROR header "Execution pair codex $m / $e is not in codex-routing.json"
    else
      say ERROR header "Execution line does not match '**Execution:** <inline|subagent> — codex <model> / <effort> — <reason>'"
    fi
  elif [[ "$execution" =~ ^\*\*Execution:\*\*\ (inline|subagent)$SEP\`?claude\ --model\ (haiku|sonnet|opus|fable|claude-[a-z0-9.-]+)\ --effort\ (low|medium|high|xhigh|max)\`?$SEP.+ ]]; then
    mode=${BASH_REMATCH[1]}
  else
    say ERROR header "Execution line does not match '**Execution:** <inline|subagent> — claude --model <m> --effort <e> — <reason>'"
  fi
fi

# --- placeholders ---
awk "$_PLAN_AWK"'
  {
    f = in_fence($0); k = f ? -1 : is_task($0)
    if (k >= 0) where = "Task " k
    s = $0; gsub(/`[^`]*`/, "", s); low = tolower(s)
    hard = (s ~ /(^|[^A-Za-z])(TBD|TODO)([^A-Za-z]|$)/ || low ~ /implement later|fill in (the )?details|similar to task [0-9]+/)
    soft = (low ~ /add appropriate error handling|handle edge cases/)
    if (hard) print (f ? "WARN " : "ERROR ") where ": placeholder: " $0
    else if (soft) print "WARN " where ": placeholder: " $0
  }
' where=header "$src" >> "$findings"

# --- per task ---
assignment=$(block assignment)
reserve=$(block reserve | awk '{ print $1 }' | grep -vxF BLOCKED | grep -vxF -f <(awk '{ print $2 }' <<<"$assignment") || true)
gate=$(block gate)
min_score=$(awk '$1 == "min_score" { print $2 }' <<<"$gate")
max_risk=$(awk '$1 == "max_risk" { print $2 }' <<<"$gate")
externals=$(grep -E '^> \*\*External executors:\*\*' <<<"$header" || true)
r5_bad=""

for n in $nums; do
  where="Task $n"
  text=$(plan_task_text "$src" "$n")
  line() { grep -m 1 -E "^\*\*$1:\*\*" <<<"$text" || true; }
  sev=ERROR
  [ -n "$(line Override)" ] && sev=WARN
  grep -qE '^\*\*Files:\*\*' <<<"$text" || say ERROR "$where" "missing **Files:** block"
  impl=$(line Implementer)
  ev=$(line Evaluation)
  [ -n "$impl" ] || say ERROR "$where" "missing **Implementer:** line"
  [ -n "$ev" ] || { say ERROR "$where" "missing **Evaluation:** line"; continue; }

  if [ "$codex" -eq 1 ]; then
    if [[ "$ev" =~ files=([0-9]+),\ spec=([0-9]+),\ coupling=([0-9]+),\ risk=([0-9]+)\;\ weighted\ routing\ score=([0-9]+) ]]; then
      a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]} s=${BASH_REMATCH[5]}
    else
      say ERROR "$where" "Evaluation does not match 'files=a, spec=b, coupling=c, risk=d; weighted routing score=s'"; continue
    fi
    [ "$s" -eq $((a + b + c + 2 * d)) ] || say ERROR "$where" "weighted routing score $s is not files+spec+coupling+2*risk = $((a + b + c + 2 * d))"
    source=$(line 'Assignment source')
    [[ "$source" =~ ^\*\*Assignment\ source:\*\*\ (rubric|human)[[:space:]]*$ ]] || say ERROR "$where" "missing or invalid **Assignment source:** (rubric|human)"
    if [[ "$source" == *rubric* ]]; then
      if [[ "$impl" =~ ^\*\*Implementer:\*\*\ \`?codex\ ([a-z0-9.-]+)\ /\ ([a-z]+)\`?[[:space:]]*$ ]]; then
        rank=$(jq -r --arg m "${BASH_REMATCH[1]}" --arg e "${BASH_REMATCH[2]}" \
          '.execution[] | select(.model == $m and .effort == $e) | .rank' "$ROUTING" 2>/dev/null | tr -d '\r')
        if [ -z "$rank" ]; then say "$sev" "$where" "Implementer pair is not an execution tier in codex-routing.json"
        elif [ "$rank" -lt "$s" ]; then say "$sev" "$where" "Implementer rank $rank is below routing score $s"
        elif [ "$rank" -gt "$s" ]; then say WARN "$where" "Implementer rank $rank is above routing score $s (promotion)"
        fi
      else
        say ERROR "$where" "Implementer does not match 'codex <model> / <effort>'"
      fi
    fi
  else
    if [[ "$ev" =~ ^\*\*Evaluation:\*\*\ files\ ([0-9]+)$SEP"spec "([0-9]+)$SEP"coupling "([0-9]+)$SEP"risk "([0-9]+)\ =\ ([0-9]+) ]]; then
      a=${BASH_REMATCH[1]} b=${BASH_REMATCH[3]} c=${BASH_REMATCH[5]} d=${BASH_REMATCH[7]} t=${BASH_REMATCH[8]}
    else
      say ERROR "$where" "Evaluation does not match 'files a — spec b — coupling c — risk d = t'"; continue
    fi
    [ "$t" -eq $((a + b + c + d)) ] || say ERROR "$where" "scores sum to $((a + b + c + d)), not $t"
    if [ -n "$impl" ]; then
      name=$(sed -E 's/^\*\*Implementer:\*\*[ \t]*`?([^` \t]+)`?.*/\1/' <<<"$impl")
      if [[ "$name" != *:* ]]; then
        say ERROR "$where" "Implementer '$name' is not fully qualified"
      else
        suffix=${name##*:} prefix=${name%%:*}
        [ "$prefix" = "dr-superpowers" ] || say WARN "$where" "legacy prefix '$prefix:' (resolved by suffix per legacy-names.md)"
        want=$(awk -v t="$t" '$1 == t { print $2 }' <<<"$assignment")
        if grep -qxF "$suffix" <<<"$reserve"; then
          say "$sev" "$where" "$suffix is a reserve tier; it needs a human **Override:**"
        elif [ "$suffix" != "$want" ]; then
          say "$sev" "$where" "Implementer $suffix does not match the assignment table's ${want:-no row} for total $t"
        fi
      fi
    fi
    approach=$(line Approach)
    if [ -n "$approach" ]; then
      if [[ "$approach" =~ ^\*\*Approach:\*\*\ (inline|advisor|best-of-3)$SEP.+ ]]; then
        [ "${BASH_REMATCH[1]}" != inline ] || [[ "$approach" =~ skip\ [0-9]+ ]] \
          || say ERROR "$where" "an inline Approach must cite 'skip <n>'"
      else
        say ERROR "$where" "Approach does not match '<inline|advisor|best-of-3> — <reason>'"
      fi
    fi
    executor=$(line Executor)
    if [ -n "$executor" ]; then
      [ "$sev" = ERROR ] || say ERROR "$where" "an Executor line on an overridden task fails the lane gate"
      { [ "$t" -ge "$min_score" ] && [ "$d" -le "$max_risk" ]; } \
        || say ERROR "$where" "total $t / risk $d fails the lane gate (min_score $min_score, max_risk $max_risk)"
      rung=$(awk -v t="$t" '$1 == t { print $2 " / " $3 }' <<<"$(block codex-assignment)")
      { [ -n "$rung" ] && [[ "$executor" == *"codex $rung"* ]]; } || say ERROR "$where" "Executor does not name the codex-assignment rung for total $t (codex ${rung:-none})"
      [[ "$externals" == *codex* ]] || say ERROR "$where" "Executor used but the header's '> **External executors:**' line does not name codex"
    fi
  fi
  for v in "$a" "$b" "$c" "$d"; do
    [ "$v" -le 3 ] || { say ERROR "$where" "each axis must be 0-3"; break; }
  done
  [ $((a + b + c)) -lt 4 ] && [ "$b" -lt 3 ] || say "$sev" "$where" "Rule S: files+spec+coupling must be below 4 and spec below 3"
  { [ $((a + b + c + d)) -le 3 ] && [ "$d" -lt 3 ]; } || r5_bad="$r5_bad $n"
done

if [ "$mode" = inline ] && [ -n "$r5_bad" ]; then
  say ERROR header "inline execution needs every task at total <= 3 and risk < 3; fails on Task${r5_bad}"
fi

cat "$findings"
errors=$(grep -c '^ERROR' "$findings" || true)
warnings=$(grep -c '^WARN' "$findings" || true)
echo "plan-lint: ${errors} errors, ${warnings} warnings"
[ "$errors" -eq 0 ]
`````

- [ ] **Step 4: Run the test to verify it passes**

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 120 bash plugins/dr-superpowers/tests/plan-lint.test.sh | tail -n 1`
Expected: `49 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add --chmod=+x plugins/dr-superpowers/scripts/plan-lint
git add plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): add plan-lint"
```

---

### Task 4: plan-amend

**Files:**
- Create: `P/scripts/plan-amend`
- Test: `P/tests/plan-amend.test.sh`

**Interfaces:**
- Consumes: `plan_apply_amendments`, `plan_task_text` from Task 1; `P/scripts/plan-lint` from Task 3 (its `ERROR` lines); `P/scripts/sdd-workspace`.
- Produces: the `plan-amend` contract in Contracts; Task 7's ruling-seat flow calls it.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

An entry is rejected only for lint errors it introduces (before/after comparison), so a pre-1.4.0 plan without a Contracts section still accepts amendments. On rejection `amendments.md` is left byte for byte as it was.

- [ ] **Step 1: Write the failing test**

Create `P/tests/plan-amend.test.sh`:

`````bash
#!/usr/bin/env bash
# plan-amend is how a controller records a plan correction without composing
# it: the entry must be well formed, apply exactly once, and add no lint
# errors, or amendments.md is left exactly as it was.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AMEND="$HERE/../scripts/plan-amend"

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
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO"
mkdir -p docs
printf '# Spec\n' > docs/spec.md
cat > docs/plan.md <<'EOF'
# Demo Implementation Plan

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4

## Global Constraints

- Bash only.

## Contracts

- `greet NAME` prints `hello NAME`.

## Assumptions (evidence)

- None.

## Task index

1. First thing
2. Second thing

### Task 1: First thing

**Files:**
- Create: `a.sh`

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

Print `hello NAME`.

### Task 2: Second thing

**Files:**
- Modify: `a.sh`

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4

Print `hello NAME` twice.
EOF
WS="$REPO/.superpowers/sdd/plan"
LEDGER="$WS/amendments.md"

entry() { # entry <file> <heading> <old> <new>
  printf '%s\nReason: the plan says the wrong thing\nCost if wrong: one fix round\n### Old\n````text\n%s\n````\n### New\n````text\n%s\n````\n' \
    "$2" "$3" "$4" > "$1"
}
run() { out=$(bash "$AMEND" "$@" 2>&1); status=$?; }

entry b1.md '## A? — Task 2' 'Print `hello NAME` twice.' 'Print `hello NAME` three times.'
run docs/plan.md b1.md
check "append: exit 0" "$status" "0"
check "append: output" "$out" "amended: A1 Task 2"
check "append: heading numbered" "$(grep -c '^## A1 — Task 2$' "$LEDGER")" "1"

entry b2.md '## Header' '- Bash only.' '- Bash 4 or later.'
run docs/plan.md b2.md
check "header target: output" "$out" "amended: A2 Header"
check "header target: blank line between entries" "$(grep -c '^$' "$LEDGER")" "1"

cp "$LEDGER" "$TMP/snapshot"
entry b3.md '## A? - Task 1' 'no such line' 'x'
run docs/plan.md b3.md
check "absent old text: exit 1" "$status" "1"
has "absent old text: reason" "$out" "rejected: Old text does not match exactly once in Task 1"
check "absent old text: file unchanged" "$(cmp -s "$LEDGER" "$TMP/snapshot" && echo same)" "same"

entry b4.md '## Task 1' '' 'x'
run docs/plan.md b4.md
has "empty old text" "$out" "rejected: Old text is empty"

entry b5.md '## Task 7' 'x' 'y'
run docs/plan.md b5.md
has "missing task" "$out" "rejected: no Task 7 in the plan"

entry b6.md '## Header' '**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4' '**Execution:** inline'
run docs/plan.md b6.md
has "protected line" "$out" "rejected: Old text touches a line that cannot be amended"

entry b7.md '## Task 2' '**Implementer:** dr-superpowers:impl-opus-low' '**Implementer:** dr-superpowers:impl-opus-high'
run docs/plan.md b7.md
check "new lint error: exit 1" "$status" "1"
has "new lint error: reason" "$out" "rejected: the amendment introduces lint errors:"
has "new lint error: named" "$out" "ERROR Task 2: Implementer impl-opus-high does not match"
check "new lint error: rolled back byte for byte" "$(cmp -s "$LEDGER" "$TMP/snapshot" && echo same)" "same"

printf '## Task 1\nReason: r\nCost if wrong: c\n### Old\n```text\nPrint `hello NAME`.\n```\n' > b8.md
run docs/plan.md b8.md
has "three-backtick fence rejected" "$out" "rejected: '### Old' and '### New' must each be followed by a closed fence"

printf 'Reason: r\n' > b9.md
run docs/plan.md b9.md
has "missing heading" "$out" "rejected: heading must be"

# A plan that already fails lint (no Contracts section) still accepts an
# amendment that adds no new error.
sed '/^## Contracts$/,/^## Assumptions/{/^## Assumptions/!d}' docs/plan.md > docs/old.md
entry b10.md '## Task 1' 'Print `hello NAME`.' 'Print `hello, NAME`.'
run docs/old.md b10.md
check "pre-existing errors: accepted" "$out" "amended: A1 Task 1"

entry b11.md '## Task 2' 'Print `hello NAME` three times.' 'Print `hello NAME` four times.'
sed 's/$/\r/' b11.md > b11-crlf.md
run docs/plan.md b11-crlf.md
check "CRLF block, builds on A1: output" "$out" "amended: A3 Task 2"

run docs/plan.md
check "usage: exit 2" "$status" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
`````

- [ ] **Step 2: Run it to verify it fails**

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 120 bash plugins/dr-superpowers/tests/plan-amend.test.sh | tail -n 1`
Expected: a summary with failures (the script does not exist yet).

- [ ] **Step 3: Write plan-amend**

Create `P/scripts/plan-amend`:

`````bash
#!/usr/bin/env bash
# Append one amendment, as the ruling seat returned it, to the plan's
# <workspace>/amendments.md — validated, numbered, and lint-checked — so the
# controller transcribes a plan correction without composing it. The plan file
# itself is never edited during execution.
#
# Usage: plan-amend PLAN_FILE BLOCK_FILE
# BLOCK_FILE heading: "## A? — Task N", "## Task N", "## A? — Header" or
# "## Header" ("-" accepted for the dash), then "Reason:", "Cost if wrong:",
# "### Old" and "### New", each followed by a fence of 4 or more backticks.
# Exit: 0 appended ("amended: A<k> <target>"); 1 rejected; 2 usage.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"

[ $# -eq 2 ] || { echo "usage: plan-amend PLAN_FILE BLOCK_FILE" >&2; exit 2; }
plan=$1 block=$2
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
[ -f "$block" ] || { echo "no such block file: $block" >&2; exit 2; }
dir=$(cd "$(dirname "$plan")" && "$HERE/sdd-workspace" "$(basename "$plan")") \
  || { echo "plan-amend needs the plan inside a git repository" >&2; exit 2; }
amend="$dir/amendments.md"
reject() { echo "rejected: $1"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tr -d '\r' < "$block" > "$TMP/block"

head_line=$(grep -m 1 -E '^## ' "$TMP/block" || true)
if [[ "$head_line" =~ ^##\ (A\?\ (—|-)\ )?(Task\ ([0-9]+)|Header)[[:space:]]*$ ]]; then
  if [ "${BASH_REMATCH[3]}" = Header ]; then target=Header n=""; else n=${BASH_REMATCH[4]} target="Task $n"; fi
else
  reject "heading must be '## A? — Task N' or '## A? — Header', got: ${head_line:-nothing}"
fi
grep -qE '^Reason: .+' "$TMP/block" || reject "missing 'Reason:' line"
grep -qE '^Cost if wrong: .+' "$TMP/block" || reject "missing 'Cost if wrong:' line"

# Split out the Old and New fence bodies; report which one is malformed.
awk -v dir="$TMP" '
  function closes(t, open) {
    sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
    return t ~ /^(`+|~+)$/ && substr(t, 1, 1) == substr(open, 1, 1) && length(t) >= length(open)
  }
  mode != "" { if (closes($0, open)) { done[mode] = 1; mode = "" } else print > (dir "/" mode); next }
  /^### Old[ \t]*$/ { sect = "old"; next }
  /^### New[ \t]*$/ { sect = "new"; next }
  sect != "" && match($0, /^(````+|~~~~+)/) { open = substr($0, RSTART, RLENGTH); mode = sect; sect = ""; printf "" > (dir "/" mode); next }
  END { if (!done["old"]) print "old" > (dir "/bad"); if (!done["new"]) print "new" >> (dir "/bad") }
' "$TMP/block"
[ ! -s "$TMP/bad" ] || reject "'### Old' and '### New' must each be followed by a closed fence of 4 or more backticks (bad: $(tr '\n' ' ' < "$TMP/bad"))"
grep -q '[^[:space:]]' "$TMP/old" || reject "Old text is empty"
if grep -qE '^(\*\*(Spec|Execution|Program|Plan review):\*\*|(\*\*)?(Host|Routing policy):)' "$TMP/old"; then
  reject "Old text touches a line that cannot be amended (Spec, Execution, Program, Plan review, Host, Routing policy)"
fi

[ -f "$amend" ] && tr -d '\r' < "$amend" > "$TMP/before" || : > "$TMP/before"
plan_apply_amendments "$plan" "$TMP/before" > "$TMP/current" 2>/dev/null \
  || reject "the existing amendments no longer apply"
if [ -n "$n" ]; then
  plan_task_text "$TMP/current" "$n" > /dev/null || reject "no Task $n in the plan"
fi

k=$(( $(sed -n 's/^## A\([0-9][0-9]*\) .*/\1/p' "$TMP/before" | sort -n | tail -n 1) + 0 + 1 ))
{
  cat "$TMP/before"
  [ -s "$TMP/before" ] && echo
  echo "## A$k — $target"
  awk 'seen { lines[++c] = $0; if (NF) last = c } /^## / && !seen { seen = 1 }
       END { for (i = 1; i <= last; i++) print lines[i] }' "$TMP/block"
} > "$TMP/after"

plan_apply_amendments "$plan" "$TMP/after" > /dev/null 2>&1 \
  || reject "Old text does not match exactly once in $target"

bash "$HERE/plan-lint" "$plan" --amendments "$TMP/before" | grep '^ERROR' | sort > "$TMP/lint-before"
bash "$HERE/plan-lint" "$plan" --amendments "$TMP/after" | grep '^ERROR' | sort > "$TMP/lint-after"
new_errors=$(comm -13 "$TMP/lint-before" "$TMP/lint-after")
[ -z "$new_errors" ] || { echo "rejected: the amendment introduces lint errors:"; printf '%s\n' "$new_errors"; exit 1; }

cp "$TMP/after" "$amend"
echo "amended: A$k $target"
`````

- [ ] **Step 4: Run the test to verify it passes**

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 180 bash plugins/dr-superpowers/tests/plan-amend.test.sh | tail -n 1`
Expected: `20 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add --chmod=+x plugins/dr-superpowers/scripts/plan-amend
git add plugins/dr-superpowers/tests/plan-amend.test.sh
git commit -m "feat(superpowers): add plan-amend"
```

---

### Task 5: Plan review criteria and prompt

**Files:**
- Create: `P/criteria/plan-review.md`
- Create: `P/skills/writing-plans/references/plan-reviewer-prompt.md`
- Delete: `P/skills/writing-plans/references/plan-document-reviewer-prompt.md`
- Test: `P/tests/criteria.test.sh` (insert a block)

**Interfaces:**
- Consumes: nothing.
- Produces: criteria ids `executability`, `coherence`, `coverage`, `assumptions`; the template Task 9's writing-plans dispatches.

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

`criteria.test.sh` checks every criteria file: a Ground Truth Note, 2–4 criteria each pinning a `{#id}`, ASCII only.

- [ ] **Step 1: Write the failing test**

In `P/tests/criteria.test.sh`, insert this block immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# plan-review.md is named by writing-plans, so its ids are a contract.
PR="$CRITERIA/plan-review.md"
check "plan-review.md exists" "$([ -f "$PR" ] && echo yes || echo no)" "yes"
if [ -f "$PR" ]; then
  got=$(grep -o '{#[a-z0-9_]\{1,\}}' "$PR" | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  check "plan-review exposes the four contracted ids" "$got" "assumptions coherence coverage executability"
fi

```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 60 bash plugins/dr-superpowers/tests/criteria.test.sh | tail -n 3`
Expected: `FAIL - plan-review.md exists` and a summary with 1 failure.

- [ ] **Step 3: Create the criteria file**

Create `P/criteria/plan-review.md` (ASCII only; write dashes as `-`):

`````markdown
# Plan Review - Verifier Criteria

Applied by dr-superpowers:writing-plans when a judge reviews an implementation
plan before it is saved.

## Ground Truth Note

Trust the plan text, the spec text, and the plan-lint output file. Do NOT trust
the planner's self-review, its task index, or its claims about what a task
covers: check each claim against the task text itself. A plan that reads as
thorough is not evidence that a small model can execute it; the exact paths,
code, and commands in each task are.

Every task's implementer sees only that task's text plus the header's Global
Constraints and Contracts. Judge each task from that view, not from your own
reading of the whole plan.

## Criteria

### Executability {#executability}

Look at each task's text together with the header's Global Constraints and
Contracts - nothing else. Score HIGH when every step names exact file paths,
every code step carries the complete code, every command is exact and states
its expected output, and every test would fail against a stub: a test that
still passes with `return <constant>` or with the implementation deleted is
invalid. Score LOW when a step leaves a decision to the implementer, refers to
something outside the task and header, says "similar to Task N", or specifies a
test that asserts nothing. Ignore whether the spec is covered; Coverage owns
that. Ignore cross-task agreement; Coherence owns that.

### Coherence {#coherence}

Look across the tasks, the Contracts section, and the Global Constraints.
Score HIGH when every name a task consumes is produced by an earlier task and
matches its Contracts entry exactly, when Interfaces blocks cite Contracts
instead of restating them, and when no two tasks contradict each other or a
Global Constraint. Score LOW for a name used before any task creates it, a
signature or path that differs between tasks or from Contracts, a task that
breaks a Global Constraint, or a Task index that disagrees with the headings.
Ignore whether the spec is covered, and ignore how well each single task is
written.

### Coverage {#coverage}

Look at the spec's requirements, section by section, against the Task index
and the task text. Score HIGH when every requirement maps to a task that
implements it and nothing is built that the spec does not ask for. Score LOW
for a requirement with no task, a requirement a task only mentions without
implementing, or a task with no requirement behind it. Ignore task quality and
cross-task agreement; the other criteria own those.

### Assumptions {#assumptions}

Look at the Assumptions (evidence) section and at the facts the tasks rely on
about existing files, tools, and behaviour. Score HIGH when every listed
assumption carries evidence that actually supports it - a command with the date
it ran, a file:line, a documentation URL - and every assumption marked
unverified has its verifying step in the named task. Score LOW when the
evidence does not show what the assumption claims, when a task relies on a
fact about the codebase or environment that is not listed, or when an
unverified assumption has no verifying step. Ignore executability and
coverage.
`````

- [ ] **Step 4: Create the reviewer prompt and delete the upstream one**

Create `P/skills/writing-plans/references/plan-reviewer-prompt.md`:

`````markdown
# Plan Reviewer Prompt Template

Use this template when dr-superpowers:writing-plans dispatches the plan review.

**Purpose:** score a finished plan against `criteria/plan-review.md` before it
is saved, so that small models can execute it literally.

**Dispatch after:** the plan is complete, self-reviewed, and `scripts/plan-lint`
reports 0 errors.

```
Subagent ([JUDGE]):
  description: "Review plan document"
  prompt: |
    You are reviewing an implementation plan before it is saved. Small models
    will execute it literally: each task's implementer sees only that task's
    text plus the header's Global Constraints and Contracts.

    **Plan:** [PLAN_FILE]
    **Spec it implements:** [SPEC_FILE]
    **plan-lint output:** [LINT_FILE] - the mechanical checks already ran; do
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

    Locate each finding by `Task N` or `header`, and say what is wrong, why it
    matters for execution, and the fix.

    ## Output Format

    ## Plan Review

    ### Findings
    - [Critical|Important|Minor] [Task N|header]: <issue> - <why> - <fix>

    ### Verification Scores
    - executability: <1-20>
    - coherence: <1-20>
    - coverage: <1-20>
    - assumptions: <1-20>

    ## Criteria

    Read the criteria file at [PLUGIN_ROOT]/criteria/plan-review.md and score
    each criterion independently on a 1 to 20 scale, where 1 is a clear
    failure, 10 is genuinely uncertain, and 20 is clearly met. Score against
    those criteria and nothing else. Where a criterion tells you to ignore
    something, ignoring it is part of scoring correctly.
```

**Placeholders:**
- `[JUDGE]` - `dr-superpowers:judge-fable`, or `dr-superpowers:judge-opus` when
  Fable is unavailable or declined (say the substitution aloud); no `model`
  argument. On Codex, a native judge at Astra high or above.
- `[PLUGIN_ROOT]` - REQUIRED: the resolved dr-superpowers plugin directory.
  Expand it before sending.
- `[PLAN_FILE]`, `[SPEC_FILE]` - REQUIRED: absolute paths.
- `[LINT_FILE]` - REQUIRED: `<workspace>/plan-lint.txt`, written with
  `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt` before dispatch.

**Reviewer returns:** findings graded Critical, Important or Minor, and four
scores. Bands: 1-8 fails, 9-13 borderline, 14-20 passes.
`````

Then delete the upstream template:

```bash
git rm plugins/dr-superpowers/skills/writing-plans/references/plan-document-reviewer-prompt.md
```

- [ ] **Step 5: Run the checks**

Run: `timeout 60 bash plugins/dr-superpowers/tests/criteria.test.sh | tail -n 1 && timeout 60 node scripts/validate-repository.mjs`
Expected: `33 passed, 0 failed`, then the validator's success line.

Run: `grep -rn 'plan-document-reviewer' plugins/ || echo none`
Expected: `none`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/criteria/plan-review.md plugins/dr-superpowers/skills/writing-plans/references/plan-reviewer-prompt.md plugins/dr-superpowers/tests/criteria.test.sh
git commit -m "feat(superpowers): add plan review criteria"
```

---

### Task 6: Ruling-seat prompt and judge descriptions

**Files:**
- Create: `P/skills/subagent-driven-development/references/ruling-prompt.md`
- Modify: `P/agents/judge-fable.md:3`, `P/agents/judge-opus.md:3`

**Interfaces:**
- Consumes: the `plan-amend` BLOCK_FILE shape from Task 4 (Contracts).
- Produces: the ruling-seat verdict block and item kinds (Contracts); Task 7 links this template.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Create the template**

Create `P/skills/subagent-driven-development/references/ruling-prompt.md`:

`````markdown
# Ruling Seat Prompt Template

Use this template when dr-superpowers:subagent-driven-development sends
judgment items to the ruling seat. That skill's The Ruling Seat section says
when, and how each verdict is carried out.

```
Subagent ([JUDGE]):
  description: "Rule on [N] item(s) at [POINT]"
  prompt: |
    You are the ruling seat for a plan being executed by a controller that
    does not own judgment. The controller reads only the plan's header and
    one task at a time; you read everything. Your verdicts are carried out
    as written, so make each one specific enough to act on without further
    judgment.

    ## Authorities

    - Spec (the binding authority): [SPEC_FILE]
    - Plan (the spec's argument): [PLAN_FILE]
    - Amendments already made to the plan: [AMENDMENTS_FILE] (may not exist)
    - Ledger (what has happened so far): [LEDGER_FILE]

    [PROVISIONAL_NOTE]

    Where the plan and the spec disagree, the spec wins. Where neither
    answers, decide, and say what it costs if you are wrong.

    You cannot modify files or dispatch subagents. Read what each item
    points at; do not crawl the codebase beyond what an item's question
    needs, and name any file you read outside the listed paths.

    ## Verdicts

    Return exactly one block per item, in item order:

        ### Item <id>
        Verdict: CONFIRMED-GAP | PARK | AMEND | BLOCKED
        Ruling: <what> — <why> — <cost if wrong>

    - CONFIRMED-GAP: the finding or gap is real. The Ruling names the
      smallest change that fixes it, precisely enough for an implementer.
    - PARK: the code stands. The finding is wrong, contestable, or real but
      built on by nothing downstream; the Ruling says which and why.
    - AMEND: the plan's text is what is wrong. After the Ruling line, write
      one amendment entry, starting at column 0, in exactly this shape
      (heading `## A? — Task <N>`, or `## A? — Header` for the header):

          ## A? — Task <N>
          Reason: <one line>
          Cost if wrong: <one line>
          ### Old
          ````text
          <whole lines copied exactly from the current plan, amendments applied>
          ````
          ### New
          ````text
          <replacement lines; may be empty>
          ````

      Old must occur exactly once in that task (its heading through the line
      before the next task heading) or in the header (everything before the
      first task). Never touch the Spec, Execution, Program, Plan review,
      Host or Routing policy lines. Never add or remove a task: a task that
      is too large is a CONFIRMED-GAP naming the split.
    - BLOCKED: every path forward is a guess. After the Ruling line, write
      `Decision needed: <what a human must decide>`.

    ## Item kinds

    - preflight: before Task 1, scan the whole plan against the spec for
      tasks that contradict each other, the Contracts or the Global
      Constraints, and for anything the plan mandates that a reviewer would
      call a defect (a test that asserts nothing, verbatim duplication of a
      logic block). First return a table: one row for every pair of tasks
      that share a file or an interface (the two tasks, what one produces
      against what the other consumes, what you found), and one row for
      every task on whether its own text agrees with itself (its tests
      against its code, the files it creates against the files it later
      touches). Then one verdict block per row that found something, with id
      `preflight-<row number>`. Rows that found nothing get no block.
    - plan-conflict: a review finding that conflicts with what the plan's
      text requires, or is labelled plan-mandated.
    - cannot-verify: a requirement the task reviewer could not verify from
      the diff. CONFIRMED-GAP means it is unmet.
    - risk3-spread: three reviews of one risk-3 task disagree by more than 6
      points on a criterion. Decide what the diff supports: CONFIRMED-GAP
      for each finding that stands, PARK otherwise.
    - breaker: findings still open after the fifth fix round.
    - blocked-plan: an implementer reported BLOCKED because the plan is
      wrong.
    - codex-empty-diff: a Codex fix round changed nothing and argues that the
      findings are already addressed or wrong. PARK accepts the argument.
    - final-residual: findings still open after the final review's one fix
      wave.

    ## Items

    Read the items file: [ITEMS_FILE]
```

**Placeholders:**
- `[JUDGE]` — `dr-superpowers:judge-fable`, or `dr-superpowers:judge-opus` when
  Fable is unavailable or declined (say the substitution aloud); no `model`
  argument. On Codex, a native judge at Astra high or above.
- `[N]`, `[POINT]` — the item count and the decision point, for the description.
- `[SPEC_FILE]`, `[PLAN_FILE]` — REQUIRED: absolute paths.
- `[AMENDMENTS_FILE]`, `[LEDGER_FILE]` — REQUIRED: `<workspace>/amendments.md`
  and `<workspace>/progress.md`.
- `[PROVISIONAL_NOTE]` — when the plan's Spec path is unreachable, "The spec is
  unreachable. Mark every Ruling (provisional)."; otherwise delete the line.
- `[ITEMS_FILE]` — REQUIRED: `<workspace>/rulings-<point>.md`, one entry per
  item: its id, kind, task (or `plan`), and the paths it needs — brief,
  report, review packages — with the findings copied verbatim.

**The seat returns** one verdict block per item (a table first for
`preflight`). Copy an AMEND entry from its `## A?` line through the New
fence's closing line into a file for `scripts/plan-amend`.
`````

- [ ] **Step 2: Update the judge descriptions**

In `P/agents/judge-fable.md`, replace the `description:` line with:

```text
description: "Read-only verifier, ruling seat and approach ranker running Fable 5 at high effort. Dispatched by dr-superpowers to score a task or plan review against criteria, rule on execution judgment items, or rank candidate approaches pairwise."
```

In `P/agents/judge-opus.md`, replace the `description:` line with:

```text
description: "Read-only verifier, ruling seat and approach ranker running Opus 5 at high effort. Dispatched by dr-superpowers in place of judge-fable when Fable is unavailable or declined, to score a task or plan review against criteria, rule on execution judgment items, or rank candidate approaches pairwise."
```

Change nothing else in either agent file.

- [ ] **Step 3: Validate**

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 60 node scripts/validate-repository.mjs && timeout 120 bash plugins/dr-superpowers/tests/fleet.test.sh | tail -n 1`
Expected: the validator's success line, then a fleet summary with `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/references/ruling-prompt.md plugins/dr-superpowers/agents/judge-fable.md plugins/dr-superpowers/agents/judge-opus.md
git commit -m "feat(superpowers): add the ruling seat prompt"
```

---

### Task 7: subagent-driven-development: the ruling seat

**Files:**
- Modify: `P/skills/subagent-driven-development/SKILL.md`

**Interfaces:**
- Consumes: `task-brief --header` and the brief's header excerpt (Task 2), `scripts/plan-amend` (Task 4), `references/ruling-prompt.md` and the item kinds (Task 6).
- Produces: the new ledger lines in Contracts; the controller procedure Task 8's references point at ("The Ruling Seat" section).

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 0 - spec 0 - coupling 2 - risk 2 = 4

Apply each edit below with an exact find-and-replace. Every "Old" block occurs exactly once unless it says "every occurrence". An "Old" block is exact text, not always whole lines (the DONE_WITH_CONCERNS one in Step 14 sits inside one long line): replace exactly the quoted text. Keep every line not named here.

- [ ] **Step 1: Rulings, not stalls (Overview)**

Old:

````text
**Rulings, not stalls.** A running plan does not wait on a human. Conflicts,
ambiguities, plan defects, a cap you would have asked to exceed, a dispatch
problem — decide them. The spec is the binding authority, the plan is its
argument, and your judgment settles what neither answers. Record every decision
in the ledger as `Ruling: <what you decided> — <why> — <what it costs if
wrong>`, say it aloud, and keep going. A wrong ruling costs rework your human
partner can see and undo; a session parked on a question costs their whole day
and buys nothing.

Four things stop you, and only these: an irreversible or destructive
operation; a security-sensitive action; a side effect outside this worktree
that norms say you ask about first (a merge, a push to a shared branch, a
publish); and a plan so broken that every path forward is a guess. For those,
stop and ask.
````

New:

````text
**Rulings, not stalls.** A running plan does not wait on a human, and it does
not wait on your judgment either. You decide the mechanical problems yourself —
the dispatch-problems table, legacy names, resuming or re-dispatching by cache
state, batching, a report missing a required section, a tool failure — and
record each in the ledger as `Ruling: <what you decided> — <why> — <what it
costs if wrong>`, said aloud. Everything that needs judgment about the plan,
the spec or a finding goes to the ruling seat (see The Ruling Seat): it reads
the whole plan and the spec, which you never read, and returns a verdict you
carry out. A wrong ruling costs rework your human partner can see and undo; a
session parked on a question costs their whole day and buys nothing.

Four things stop you, and only these: an irreversible or destructive
operation; a security-sensitive action; a side effect outside this worktree
that norms say you ask about first (a merge, a push to a shared branch, a
publish); and a ruling-seat `BLOCKED` verdict — a plan so broken that every
path forward is a guess. For those, stop and ask.
````

- [ ] **Step 2: Process graph node names (every occurrence of each)**

Replace every occurrence (node declarations and edges alike):

| Old | New |
|---|---|
| `"Setup: worktree, ledger check, read plan, legacy names, pre-flight review"` | `"Setup: worktree, ledger check, plan header, legacy names, pre-flight ruling"` |
| `"Rule on the conflict, ledger the ruling"` | `"Ruling seat rules on the conflict (./references/ruling-prompt.md)"` |
| `"Adjudicate each open finding"` | `"Ruling seat adjudicates each open finding"` |
| `"Any load-bearing finding?"` | `"Any CONFIRMED-GAP or AMEND?"` |
| `"Rule and continue; stop only if every path forward is a guess"` | `"Carry the fix or amendment forward; BLOCKED stops"` |
| `"Final findings? ONE fix dispatch, one scoped re-review, adjudicate residuals"` | `"Final findings? ONE fix dispatch, one scoped re-review, ruling seat on residuals"` |

- [ ] **Step 3: Setup reads the header, not the plan**

Old:

````text
Read the plan once, note its context and Global Constraints, and create a
todo per task. If the plan names a Spec, read that too: the spec is the
authority the plan argues from, and conflicts inside the plan resolve
against it. A plan with no reachable spec gets a ledger note saying so —
rulings made without one are provisional.
````

New:

````text
Read the plan's header, never the whole plan: run
`scripts/task-brief --header PLAN_FILE`, from the plugin root, and read the
file it prints (`<workspace>/plan-header.md`). Note the Execution line, the
Global Constraints and the Contracts, and create a todo per Task index entry.
A plan written before 1.4.0 may have no Task index: then run
`scripts/task-brief PLAN_FILE N` for N = 1, 2, … until it exits 3, and take
each task's title from its brief's first line. You never read the spec: the
ruling seat, the plan review and the final review do. If the plan's
`**Spec:**` path is unreachable, note it in the ledger and say so in every
ruling-seat dispatch; the seat marks its rulings provisional.
````

- [ ] **Step 4: The pre-flight scan goes to the seat**

Old:

````text
Before dispatching Task 1, scan the plan once for conflicts, writing down
what you checked as you check it:

- tasks that contradict each other or the plan's Global Constraints
- anything the plan explicitly mandates that the review rubric treats as a
  defect (a test that asserts nothing, verbatim duplication of a logic block)

The scan's output is a table, not a verdict. One row for every pair of tasks
that share a file or an interface: the two tasks, what one produces against
what the other consumes, and what you found. One row for every task: whether
its own text agrees with itself — the tests it specifies against the code it
specifies, the files it creates against the files it later touches. "The scan
is clean" without those rows is not a scan you ran.

Write the table to the ledger. Rule on everything you find before execution
begins — each finding against the plan text that mandates it — and record
each ruling in the ledger. If the scan is clean, proceed without comment.
Rule on each conflict it surfaces — the spec is the binding authority, the
plan is its argument — record the ruling beside its row, and dispatch
Task 1. The review loop remains the net for conflicts that only emerge from
implementation.
````

New:

````text
Before dispatching Task 1, send one `preflight` item to the ruling seat (see
The Ruling Seat). It scans the whole plan against the spec for:

- tasks that contradict each other, the Contracts, or the Global Constraints
- anything the plan explicitly mandates that the review rubric treats as a
  defect (a test that asserts nothing, verbatim duplication of a logic block)

The seat returns a table, not a verdict: one row for every pair of tasks that
share a file or an interface, and one row for every task on whether its own
text agrees with itself. Verdict blocks follow for the rows that found
something. Write the whole output to `<workspace>/preflight.md`, carry out
each verdict, log `Ruling: pre-flight — <clean | K findings, see
preflight.md> — none`, and dispatch Task 1. A resumed ledger that already
holds that line skips the dispatch. The review loop remains the net for
conflicts that only emerge from implementation.
````

- [ ] **Step 5: Seats table gains the ruling seat**

Old:

````text
| Scoped re-review | general-purpose | Explicit, cheap-to-mid |
````

New:

````text
| Ruling seat | `dr-superpowers:judge-fable`; `dr-superpowers:judge-opus` under the same rule | None |
| Scoped re-review | general-purpose | Explicit, cheap-to-mid |
````

- [ ] **Step 6: Ledger grammar**

Old:

````text
Task <N>: BLOCKED — <agent> exhausted — <what a human must decide>
````

New:

````text
Task <N>: BLOCKED — <agent> exhausted — <what a human must decide>
Task <N>: BLOCKED — ruling seat — <what a human must decide>
Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>
Ruling: amendment A<k> (Header) — <reason> — <cost if wrong>
````

Old:

````text
- Write each line in the same message as your other bookkeeping, never later.
````

New:

````text
- Write each line in the same message as your other bookkeeping, never later.
- A ruling-seat `BLOCKED` that belongs to no task (a `preflight` row, a
  Header amendment) is logged against the lowest-numbered task without a
  complete line, so recovery reads it as that task's terminal line.
````

Old:

````text
| `fix round 5/5` or `review round 5/5` | Go to the breaker and adjudicate |
````

New:

````text
| `fix round 5/5` or `review round 5/5` | Go to the breaker |
````

- [ ] **Step 7: New section "The Ruling Seat"**

Insert this section immediately before the line `## Session Budget`:

````text
## The Ruling Seat

Judgment belongs to the ruling seat, never to you, whatever model you run on.
It reads the whole plan, the spec, `amendments.md` and the ledger; you read
the header and one brief at a time.

**When.** Send the seat an item at each of these points, batching every item
that arises at one point into one dispatch:

| Kind | Decision point |
|---|---|
| `preflight` | Once, before Task 1 (Setup) |
| `plan-conflict` | A review finding labelled plan-mandated, or one that conflicts with what the plan's text requires |
| `cannot-verify` | Every "⚠️ Cannot verify from diff" item, before the task completes |
| `risk3-spread` | A risk-3 criterion whose three scores spread by more than 6 points |
| `breaker` | Every finding still open after round 5/5 |
| `blocked-plan` | An implementer BLOCKED because the plan is wrong |
| `codex-empty-diff` | A Codex fix round that returned DONE with an empty diff and an argument ([external-executor.md](../../reference/external-executor.md)) |
| `final-residual` | Findings still open after the final review's one fix wave |

**How.** Write `<workspace>/rulings-<point>.md` listing each item: an id, its
kind, its task (or `plan`), and the paths it needs — brief, report, review
packages — with the findings copied verbatim. Dispatch
`dr-superpowers:judge-fable` (`judge-opus` under the Fable-unavailable rule,
said aloud) with [ruling-prompt.md](references/ruling-prompt.md), expanding
its placeholders. Codex hosts use a native judge at Astra high or above
([native-codex.md](../../reference/native-codex.md)).

**Carry out each verdict**, and copy its `Ruling:` line into the ledger
verbatim:

- **CONFIRMED-GAP** — the finding is real. Mid-task it enters the fix loop
  with the ruling's smallest fix in the fix message. At the breaker it is
  logged `Task <N>: Ruling: <finding> — <ruling>` and carried into the next
  dependent task's dispatch.
- **PARK** — log `Task <N>: parked — <finding> — Ruling: <why>`; the code
  stands.
- **AMEND** — copy the entry, from its `## A?` line through the New fence's
  closing line, to `<workspace>/amend-<id>.md` and run
  `scripts/plan-amend PLAN_FILE <workspace>/amend-<id>.md`, from the plugin
  root. On `amended: A<k> …`, write the amendment ledger line; the next
  dispatch uses a fresh `task-brief`, which carries the amendment. On
  `rejected: …`, make one fresh seat dispatch carrying the entry and the
  rejection output; a second rejection is BLOCKED.
- **BLOCKED** — log `Task <N>: BLOCKED — ruling seat — <decision>`, name it
  in your final message, and stop.

Never soften, merge or second-guess a verdict. If you think the seat is
wrong, carry the verdict out anyway: the ledger line is where your human
partner sees it.

````

- [ ] **Step 8: The task loop reads briefs only**

Old:

````text
its own review surface. A batched task never runs on an external executor.
````

New:

````text
its own review surface. A batched task never runs on an external executor.
Decide batching from the briefs of the contiguous candidate tasks, extracted
with `task-brief`; you never read task text any other way.
````

Old:

````text
  first — it is your requirements, with the exact values to use verbatim";
````

New:

````text
  first — it is your requirements, with the exact values to use verbatim,
  and it ends with the plan's Global Constraints and Contracts";
````

Old:

````text
  was pasted history. A fresh subagent needs its task, the interfaces it
  touches, and the global constraints. Nothing else.
````

New:

````text
  was pasted history. A fresh subagent needs its brief, which already
  carries its task, the Contracts and the Global Constraints. Nothing else.
````

Old:

````text
4. If the plan itself is wrong, rule on the correction, ledger it, and re-dispatch with the ruling carried in the dispatch
````

New:

````text
4. If the plan itself is wrong, send a `blocked-plan` item to the ruling seat and carry out its verdict; an AMEND re-dispatches from a fresh brief
````

- [ ] **Step 9: Review inputs, scores, risk 3, ⚠️ items**

Old:

````text
- **Reviewer inputs:** the brief file, the report file, and the review
  package — plus the global constraints that bind the task. Never tell the
  reviewer which lane produced the diff: a judge that knows the author scores
  the author.
- The global-constraints block you hand the reviewer is its attention
  lens. Copy the binding requirements verbatim from the plan's Global
  Constraints section or the spec: exact values, exact formats, and the
  stated relationships between components ("same layout as X", "matches
  Y"). The reviewer's template already carries the process rules (YAGNI,
  test hygiene, review method) — the constraints block is for what THIS
  project's spec demands.
````

New:

````text
- **Reviewer inputs:** the brief file (it ends with the plan's Global
  Constraints and Contracts — the reviewer's attention lens), the report
  file, and the review package. Never tell the reviewer which lane produced
  the diff: a judge that knows the author scores the author.
````

Old:

````text
fails** and joins the fix-loop trigger; **9-13** is borderline, recorded and
adjudicated by you; **14-20 passes**. The verdicts still drive the loop; a
````

New:

````text
fails** and joins the fix-loop trigger; **9-13** is borderline, recorded on
the complete line for the final review to triage, never adjudicated by you;
**14-20 passes**. The verdicts still drive the loop; a
````

Old:

````text
scores for any criterion spread by more than 6 points, read the diff yourself
rather than trusting the average: the criterion failed to discriminate on this
````

New:

````text
scores for any criterion spread by more than 6 points, send a `risk3-spread`
item with the three reviews to the ruling seat rather than trusting the
average: the criterion failed to discriminate on this
````

Old:

````text
review, but you must resolve each one yourself before marking the task
complete: you hold the plan and cross-task context the reviewer
lacks. If you confirm an item is a real gap, treat it as a failed spec
review — it enters the fix loop with the other findings.
````

New:

````text
review, but each goes to the ruling seat as a `cannot-verify` item before
the task completes: the seat holds the plan and cross-task context the
reviewer lacks. A CONFIRMED-GAP is a failed spec review — it enters the fix
loop with the other findings.
````

Old:

````text
or a ⚠️ item you confirmed as a real gap.
````

New:

````text
or a ⚠️ item the ruling seat confirmed as a gap.
````

- [ ] **Step 10: The fix loop and the breaker**

Old:

````text
- A finding labeled plan-mandated — or any finding that conflicts with
  what the plan's text requires — is yours to rule on: weigh the finding
  against the plan text, decide with the spec as the binding authority, and
  ledger the ruling before you act on it. Do not dismiss the finding because
  the plan mandates it, and do not dispatch a fix that contradicts the plan
  without a recorded ruling.
````

New:

````text
- A finding labeled plan-mandated — or any finding that conflicts with
  what the plan's text requires — goes to the ruling seat as a
  `plan-conflict` item before you act on it. Do not dismiss the finding
  because the plan mandates it, and do not dispatch a fix that contradicts
  the plan without the seat's verdict in the ledger.
````

Old:

````text
**The breaker.** When round 5's re-review still leaves findings open, stop
dispatching. Adjudicate each open finding yourself — you hold the plan and
the cross-task context the reviewer lacks:

- **The reviewer is wrong, or the point is contestable:** park it —
  `Task <N>: parked — <finding> — Ruling: <why the code stands>`. The final
  review sees both sides.
- **Real, but nothing downstream builds on it:** park it the same way, with
  a ruling that says it's real and deferred.
- **Real and load-bearing** — a later task builds on it, or it reveals a
  plan defect: rule on the smallest change that unblocks the dependent work,
  ledger it as `Task <N>: Ruling: <finding> — <what you decided and why>`,
  and carry it into the next task's dispatch. Parking a structural failure
  silently lets every dependent task build on it. Stop only when the defect
  leaves every path forward a guess.

Adjudicate only at the cap. Adjudicating earlier to end a loop is
pre-judging with a different name. Every adjudication is a ledger entry —
a silent discard is forbidden.
````

New:

````text
**The breaker.** When round 5's re-review still leaves findings open, stop
dispatching and send every open finding to the ruling seat in one `breaker`
dispatch. The seat parks a finding that is wrong, contestable, or real but
built on by nothing downstream; returns CONFIRMED-GAP with the smallest
unblocking change for one a later task builds on; AMEND for a plan defect;
and BLOCKED when every path forward is a guess. Carry out each verdict (see
The Ruling Seat). Parking a structural failure silently lets every dependent
task build on it, which is why the seat, not you, decides.

Send findings to the breaker only at the cap. Ending a loop earlier is
pre-judging with a different name. Every verdict is a ledger entry — a silent
discard is forbidden.
````

- [ ] **Step 11: Final Review**

Old:

````text
   Point it at the ledger's deferred-minor and parked lines and the complete
   lines' `discovered:` fields, so it can triage which must be fixed before
   merge.
````

New:

````text
   Point it at the ledger's deferred-minor and parked lines, the complete
   lines' `discovered:` fields, and every borderline (9-13) score, so it can
   triage which must be fixed before merge.
````

Old:

````text
3. **Dedupe** into one list, tagging each finding `claude`, `codex`, or `both`.
   Two findings are the same when they name the same defect in the same place,
   not merely the same file.
4. **Verify** every finding with `dr-superpowers:judge-fable` (`judge-opus`
   under the Fable-unavailable rule) in one dispatch for the whole list,
   returning `CONFIRMED` or `REJECTED` with evidence for each. The verifier is a
   third seat, so neither reviewer grades its own work.
5. **Report** confirmed findings ranked most severe first, then the rejected
   ones with the reason each was rejected. A finding both reviewers raised and
   the judge confirmed is the strongest signal available in this loop; say so.
````

New:

````text
3. **Dedupe and verify** in one dispatch of `dr-superpowers:judge-fable`
   (`judge-opus` under the Fable-unavailable rule) given both reviewers'
   lists. It merges findings that name the same defect in the same place (not
   merely the same file), tags each `claude`, `codex`, or `both`, and returns
   `CONFIRMED` or `REJECTED` with evidence for each. The verifier is a third
   seat, so neither reviewer grades its own work.
4. **Report** confirmed findings ranked most severe first, then the rejected
   ones with the reason each was rejected. A finding both reviewers raised and
   the judge confirmed is the strongest signal available in this loop; say so.
````

Old:

````text
[re-review-prompt.md](references/re-review-prompt.md)). Adjudicate any residual
findings as in the task loop's breaker: park with rulings, or rule on the
load-bearing ones and ledger what you decided. Only the four classes above stop
````

New:

````text
[re-review-prompt.md](references/re-review-prompt.md)). Send any residual
findings to the ruling seat as `final-residual` items and carry out its
verdicts. Only the four classes above stop
````

- [ ] **Step 12: Finish prints the amendments**

Old:

````text
workspace was a decision made in secret. Name every `BLOCKED` task there too.
````

New:

````text
workspace was a decision made in secret. Name every `BLOCKED` task there too.

Then, under "Amendments made", print every entry of `<workspace>/amendments.md`
in full, if the file exists. The workspace is deleted after a merge, so this
printed list is the only lasting record of how the plan changed during
execution.
````

- [ ] **Step 13: Rationalizations and the example**

Old:

````text
| "This finding is obviously wrong, I'll drop it" | You adjudicate only at the cap, and every ruling is a ledger entry. Silent discards are forbidden. |
````

New:

````text
| "This finding is obviously wrong, I'll drop it" | The ruling seat adjudicates, only at the cap, and every verdict is a ledger entry. Silent discards are forbidden. |
| "I can see the plan is wrong, I'll rule on it myself" | You read the header and one brief; the seat reads the plan and the spec. Send it a plan-conflict item. |
````

Old:

````text
[Read plan file once: docs/superpowers/plans/feature-plan.md]
````

New:

````text
[task-brief --header docs/superpowers/plans/feature-plan.md; read plan-header.md, never the whole plan]
````

Old:

````text
[Create todos for all tasks]
````

New:

````text
[Create todos for all tasks]
[Pre-flight: ruling seat returns preflight.md — clean; ledger the pre-flight ruling]
````

- [ ] **Step 14: Remove the remaining controller judgment**

Old:

````text
Mode switches between this skill and dr-superpowers:executing-plans happen only
at a task boundary where every earlier task is complete, recorded as a
`Ruling:` line.
````

New:

````text
The plan's `**Execution:**` line decides the mode. Only your human partner's
explicit instruction switches it, and only at a task boundary where every
earlier task is complete, recorded as a `Ruling:` line.
````

Old:

````text
  know; (4) your resolution of any ambiguity you noticed in the brief —
  including, when the brief names a skill under an old plugin prefix, that
  legacy names resolve per `reference/legacy-names.md`; (5) the report-file
````

New:

````text
  know; (4) the ruling-seat verdicts in the ledger that bear on this task,
  copied verbatim (an ambiguity you notice in the brief goes to the seat as a
  `plan-conflict` item before you dispatch) — and, when the brief names a
  skill under an old plugin prefix, that legacy names resolve per
  `reference/legacy-names.md`; (5) the report-file
````

Old:

````text
Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations
````

New:

````text
Read the concerns before proceeding. If the concerns are about correctness or scope, pass them to the task reviewer with its other inputs; the review loop decides them. If they're observations
````

Old:

````text
3. If the task is too large, break it into smaller pieces
````

New:

````text
3. If the task is too large, send a `blocked-plan` item; a split is the seat's CONFIRMED-GAP naming it, logged as a `Ruling:` line
````

Old:

````text
  false positive, let the reviewer raise it and adjudicate it in the review
  loop. If the prompt you are writing contains "do not flag," "don't treat X
````

New:

````text
  false positive, let the reviewer raise it; the review loop and, at the
  cap, the ruling seat decide it. If the prompt you are writing contains "do not flag," "don't treat X
````

Old:

````text
preflight rulings, dispatch rulings, translations, parked findings, breaker
adjudications, all of them — into your final message under "Rulings I made",
````

New:

````text
preflight rulings, dispatch rulings, translations, parked findings, ruling-seat
verdicts, all of them — into your final message under "Rulings I made",
````

Old:

````text
| "Close enough on spec compliance" | Reviewer found spec gaps = not done. Fix or hit the cap and adjudicate — those are the only exits. |
````

New:

````text
| "Close enough on spec compliance" | Reviewer found spec gaps = not done. Fix, or hit the cap and send it to the ruling seat — those are the only exits. |
````

Old:

````text
| "One more round will converge" | Past the cap, rounds don't converge — the failure is structural. Adjudicate and route. |
````

New:

````text
| "One more round will converge" | Past the cap, rounds don't converge — the failure is structural. Send it to the breaker and carry out the seat's verdicts. |
````

Old:

````text
[Dedupe; judge-fable verifies the union: 1 CONFIRMED (both), 1 REJECTED]
````

New:

````text
[judge-fable dedupes and verifies the union: 1 CONFIRMED (both), 1 REJECTED]
````

- [ ] **Step 15: Verify no old wording survives**

Run:

```bash
cd plugins/dr-superpowers/skills/subagent-driven-development
grep -c 'The Ruling Seat' SKILL.md
grep -c 'djudicat' SKILL.md
grep 'djudicat' SKILL.md | grep -vc 'uling seat adjudicates'
grep -nE 'adjudicated by you|read the diff yourself|resolve each one yourself|is yours to rule on|Read the plan once|your resolution of any ambiguity|break it into smaller pieces' SKILL.md || echo clean
cd - >/dev/null
timeout 60 node scripts/validate-repository.mjs
```

Expected: a count of at least `4`; then `4` (three process-graph lines and one rationalization row, all saying the ruling seat adjudicates); then `0`; then `clean`; then the validator's success line.

- [ ] **Step 16: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md
git commit -m "feat(superpowers): route judgment to the ruling seat"
```

---

### Task 8: Execution references route judgment to the seat

**Files:**
- Modify: `P/skills/subagent-driven-development/references/implementer-prompt.md`
- Modify: `P/skills/subagent-driven-development/references/task-reviewer-prompt.md`
- Modify: `P/reference/external-executor.md`
- Modify: `P/skills/resume-execution/SKILL.md`
- Modify: `P/skills/finishing-a-development-branch/SKILL.md`

**Interfaces:**
- Consumes: the brief's header excerpt (Task 2); the item kinds and "The Ruling Seat" section (Tasks 6–7).
- Produces: nothing new.

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

Exact find-and-replace edits; each Old block occurs once. Keep every other line.

- [ ] **Step 1: implementer-prompt.md**

Old:

````text
    Read your task brief first: [BRIEF_FILE]
    It contains the full task text from the plan.
````

New:

````text
    Read your task brief first: [BRIEF_FILE]
    It contains the full task text from the plan, and ends with the plan
    header's Global Constraints and Contracts: the exact names, signatures
    and values other tasks use. Use them verbatim.
````

Old:

````text
    Work from: [directory]
````

New:

````text
    Work from: [directory]

    **Keep it small and surgical:** do the simplest thing the brief allows,
    and touch only the files and lines the task needs.
````

Old:

````text
    - You've been reading file after file trying to understand the system without progress
````

New:

````text
    - You've been reading file after file trying to understand the system without progress
    - You are about to try a third fix for the same failure: stop and question
      the assumption behind the first two
    - The same test still fails after three edits: report BLOCKED with what
      you tried
````

- [ ] **Step 2: task-reviewer-prompt.md**

Old:

````text
    Read the task brief: [BRIEF_FILE]

    Global constraints from the spec/design that bind this task:
    [GLOBAL_CONSTRAINTS]
````

New:

````text
    Read the task brief: [BRIEF_FILE]

    The brief ends with the plan header's Global Constraints and Contracts.
    They bind this task: exact values, formats, and the names other tasks use.
````

Old:

````text
    plan-mandated. The plan's authorship does not grade its own work; the
    human decides.
````

New:

````text
    plan-mandated. The plan's authorship does not grade its own work; the
    ruling seat decides.
````

Delete these four lines from the Placeholders list:

````text
- `[GLOBAL_CONSTRAINTS]` — the binding requirements copied verbatim from
  the plan's Global Constraints section or the spec: exact values, formats,
  and stated relationships between components (not process rules — those
  are already in this template)
````

- [ ] **Step 3: external-executor.md**

Old:

````text
if it argues the findings are already addressed or wrong, adjudicate that claim
yourself the way subagent-driven-development has you adjudicate any disputed
finding, and record the ruling. Do not re-dispatch the round to force a diff. Two
````

New:

````text
if it argues the findings are already addressed or wrong, send that claim to
the ruling seat as a `codex-empty-diff` item (subagent-driven-development, The
Ruling Seat) and carry out its verdict. Do not re-dispatch the round to force a diff. Two
````

Old:

````text
| A fix round returned DONE with an empty diff | Codex read the findings and changed nothing on purpose. Adjudicate the report's argument rather than re-dispatching; two in a row is a stalled loop and a `HANDBACK` |
````

New:

````text
| A fix round returned DONE with an empty diff | Codex read the findings and changed nothing on purpose. Send the report's argument to the ruling seat as a `codex-empty-diff` item rather than re-dispatching; two in a row is a stalled loop and a `HANDBACK` |
````

- [ ] **Step 4: resume-execution/SKILL.md**

Old:

````text
4. **Reload** `<workspace>/handoff.md`, the plan's header (everything above its
   first `### Task`), and the ledger. The owner constraints and do-nots in
````

New:

````text
4. **Reload** `<workspace>/handoff.md`, the plan's header (run
   `scripts/task-brief --header PLAN_FILE` and read the file it prints), and
   the ledger. The owner constraints and do-nots in
````

- [ ] **Step 5: finishing-a-development-branch/SKILL.md**

Old:

````text
has not yet printed its "Rulings I made" list, print it now: every ledger line
containing `Ruling:`, in order. Your human partner chooses how to integrate
with those decisions in view.
````

New:

````text
has not yet printed its "Rulings I made" and "Amendments made" lists, print
them now: every ledger line containing `Ruling:`, in order, then every entry
of `amendments.md` in the same directory, in full. Your human partner chooses
how to integrate with those decisions in view.
````

- [ ] **Step 6: Verify**

Run:

```bash
grep -rn 'GLOBAL_CONSTRAINTS' plugins/dr-superpowers || echo clean
grep -c 'codex-empty-diff' plugins/dr-superpowers/reference/external-executor.md
timeout 60 node scripts/validate-repository.mjs
```

Expected: `clean`, `2`, then the validator's success line.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/references/implementer-prompt.md plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dr-superpowers/reference/external-executor.md plugins/dr-superpowers/skills/resume-execution/SKILL.md plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md
git commit -m "feat(superpowers): route references to the seat"
```

---

### Task 9: writing-plans: header, lint, review, handoff

**Files:**
- Modify: `P/skills/writing-plans/SKILL.md` (full replacement)
- Modify: `P/skills/writing-plans/references/assigning-implementers.md`
- Modify: `P/reference/session-budget.md:50-53`

**Interfaces:**
- Consumes: `scripts/plan-lint` (Task 3), `criteria/plan-review.md` and `references/plan-reviewer-prompt.md` (Task 5), `dr-superpowers:handoff`.
- Produces: the plan format in Contracts (header block, `**Override:**`, `**Plan review:**`, Execution line choice).

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Replace writing-plans/SKILL.md**

Replace the whole of `P/skills/writing-plans/SKILL.md` with:

`````markdown
---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well. Small models execute these plans literally: each task's implementer sees only that task's text plus the header's Global Constraints and Contracts.

**Keep it minimal and checkable:** no speculative abstractions; each task is the minimum that meets the spec; each task ends with a check that proves it.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `dr-superpowers:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

**Walking skeleton:** for a greenfield system, Task 1 builds the thinnest end-to-end path through every layer, with its test, before any layer is fleshed out.

## Task Right-Sizing

A task is the smallest unit that carries its own test cycle and is worth a
fresh reviewer's gate. When drawing task boundaries: fold setup,
configuration, scaffolding, and documentation steps into the task whose
deliverable needs them; split only where a reviewer could meaningfully
reject one task while approving its neighbor. Each task ends with an
independently testable deliverable.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header.** Everything before the first
`### Task` heading is the header. Execution controllers read only the header
and one task at a time, and every task brief carries the header's Global
Constraints and Contracts.

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** [path to the spec/design doc this plan implements]

**Execution:** [inline|subagent] — `claude --model <model> --effort <effort>` — [why]

**Program:** [only when the spec is one sub-project of a program design:
`<program spec path>` — sub-project <k> of <n> — next: <title of sub-project
k+1, copied from the program's decomposition>. On the final sub-project,
end with `— last` instead of `— next: …`. Omit the line otherwise.]

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits,
naming and copy rules, platform requirements — one line each, with exact
values copied verbatim from the spec. Every task's requirements implicitly
include this section.]

## Contracts

[Every name, signature, file path, format or exit code that one task
produces and another consumes, stated once. Task Interfaces blocks cite this
section rather than restate it. Write `None` when no task consumes another's
output.]

## Assumptions (evidence)

[One bullet per assumption the plan relies on, each with its evidence: a
command and the date it ran, a `file:line`, or a documentation URL. An
assumption you could not verify reads `unverified — Task N verifies it`, and
Task N contains the verifying step.]

## Task index

1. [Task 1 title, identical to its heading]
2. [...]

---
```

Codex plans also carry `Host: codex` and `Routing policy: codex-v2` lines
([native-codex.md](../../reference/native-codex.md)), and their Execution line
names the native pair: `**Execution:** <inline|subagent> — codex <model> / <effort> — <why>`.

**Choosing the Execution line.** The plan decides its execution mode:

- `inline` when every task's total is 3 or less and no task is at risk 3 —
  the default then: `claude --model sonnet --effort <e>`, where `<e>` is the
  effort of the highest-scoring task's assigned tier (`impl-haiku` counts as
  `low`).
- Otherwise `subagent`: `claude --model sonnet --effort high`. The controller
  owns no judgment calls — the ruling seat does — so it needs no stronger
  model.
- Your human partner may override the line; `plan-lint` checks its grammar and
  the inline rule.

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — cite the Contracts entry]
- Produces: [what later tasks rely on — cite the Contracts entry. A task's
  implementer sees only their own task plus Global Constraints and
  Contracts; this block is how they learn which names they touch.]

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## Assign an implementer to every task

Every task records which implementer runs it, so the choice is a property of
the plan rather than a judgment made from memory at dispatch time. Do this
after the tasks are drafted and before the plan is saved. Retrofitting an
existing plan is the same process: read it, resolve names written under older
plugin prefixes with [legacy-names.md](../../reference/legacy-names.md) (a name
outside that table: ask), score each task, and add the lines.

**Codex host:** follow [native-codex.md](../../reference/native-codex.md) — its
`codex-v2` selector, plan headers, assignment-source fields, and conversion
rules replace the Claude table, fleet, and external CLI lane below. Honor the
user's inline or delegation preference on either host.

1. **Score** each task on the four axes in
   [ladder.md](../../reference/ladder.md) — files, spec completeness,
   coupling, risk. Never restate its tables or work from memory. Score the
   task as its brief will carry it — the task text plus the header's Global
   Constraints and Contracts: if those contain the complete code and exact
   signatures, spec completeness is 0. Count file shapes, not file instances.
2. **Apply Rule S before the table.** If `files + spec + coupling >= 4`, split
   the task where a reviewer could reject one half while approving the other,
   and re-score both halves. If `spec = 3`, the approach is undecided: settle
   it with dr-superpowers:selecting-approaches, rewrite the task with the
   decision in its steps, and re-score. Never answer a reducible axis with a
   bigger model.
3. **Assign** from the assignment table, which the total indexes directly.
   Never assign a reserve agent — any `xhigh` or `max` effort, any Fable
   tier. Only a human edit puts one in a plan.
4. **Offer an external executor** once per plan and apply the lane gate — see
   [external-executor.md](../../reference/external-executor.md) §Planning. If
   no executor is usable, ask nothing.
5. **Write the lines** directly below the task's `**Interfaces:**` block, in
   this order:
   - `**Implementer:**` — always; the fully qualified agent, for example
     `dr-superpowers:impl-sonnet-medium`
   - `**Executor:**` — only when the lane gate passed, for example
     `codex gpt-5.5 / medium`
   - `**Evaluation:**` — always, for example
     `files 0 - spec 1 - coupling 1 - risk 0 = 2`
   - `**Approach:**` — only when the task involved an approach decision:
     `inline`, `advisor`, or `best-of-3`, a dash, and a one-line reason; an
     `inline` reason cites a skip condition by number

   ```markdown
   **Implementer:** dr-superpowers:impl-opus-medium
   **Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5
   **Approach:** inline - skip 2: follows the existing exporter pattern
   ```

6. **Keep the heading form** `### Task N: <name>`: `scripts/task-brief` finds a
   task by a heading that begins with `Task <N>`.

A human may edit any `**Implementer:**` line by hand;
dr-superpowers:subagent-driven-development obeys it and never recomputes.
Leave the `**Evaluation:**` line in place — the gap between the score and the
choice is the interesting part. A hand edit that breaks a checked rule — a
reserve tier, a kept `spec = 3`, a table mismatch — carries an
`**Override:** <reason>` line below the Evaluation line, and `plan-lint` then
reports it as a warning. Never write an Override line yourself. Under
dr-superpowers:executing-plans the lines are inert.
[assigning-implementers.md](references/assigning-implementers.md) explains why
each of these rules exists.

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Contracts:** Every cross-task name appears in Contracts, and every task uses it exactly as stated there. A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Lint:** Run the checker under Lint and Review.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Lint and Review

1. **Lint.** Run `scripts/plan-lint PLAN_FILE`, from the plugin root (two
   levels above this skill's directory), until it reports `0 errors`. Fix each
   WARN, or explain it in one line of the plan's Assumptions. The checker
   covers the header sections, the task headings and index, the Execution
   line, placeholders, and every task's assignment lines.
2. **Review.** Write the lint output to the plan's workspace:
   `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt`, where
   `<workspace>` is the directory `scripts/sdd-workspace PLAN_FILE` prints.
   Dispatch the judge with
   [plan-reviewer-prompt.md](references/plan-reviewer-prompt.md). It scores
   executability, coherence, coverage and assumptions (1-20) against
   [plan-review.md](../../criteria/plan-review.md) and lists findings.
3. **Fix and repeat.** Any score of 8 or below, or any Critical or Important
   finding: fix the plan, re-lint, and dispatch a fresh full review. At most 3
   review rounds; after the third, show the remaining findings to your human
   partner. A borderline score (9-13) gets a one-line decision in the plan's
   Assumptions.
4. **Record.** Only now, add the header line
   `**Plan review:** <YYYY-MM-DD> — <judge agent> — executability e / coherence c / coverage v / assumptions a (round r)`
   below the `**Program:**` line (below `**Execution:**` when there is no
   Program line). The header template deliberately omits it, so `plan-lint`
   warns until the review has run.

## Execution Handoff

A saved, reviewed plan is a hard stop: execution starts in a fresh session.
Invoke dr-superpowers:handoff. It commits the plan and the spec, writes
`.superpowers/handoff/latest.md`, runs `scripts/next-step PLAN_FILE`, and ends
your message with the resume guide — the launch command from the Execution
line and the first prompt for the skill that line names. Offer no execution
choice: the Execution line already made it.
`````

- [ ] **Step 2: assigning-implementers.md**

Old:

````text
fine. That is why the check runs over all headings as a set: a single
`task-brief` run only inspects the heading you asked for.
````

New:

````text
fine. That is why `scripts/plan-lint` checks all headings as a set: a single
`task-brief` run only inspects the heading you asked for.
````

Old:

````text
present, so a human ruling always wins over the rubric. The `**Evaluation:**`
line stays, because the gap between the score and the choice is the interesting
part.
````

New:

````text
present, so a human ruling always wins over the rubric. The `**Evaluation:**`
line stays, because the gap between the score and the choice is the interesting
part.

A hand edit that breaks a rule the checker enforces - a reserve tier, a kept
`spec = 3`, a table mismatch - carries an `**Override:** <reason>` line below
the Evaluation line, and `plan-lint` reports those findings on that task as
warnings instead of errors. Planners never write the line: it is how a human
ruling stays legal without the checker guessing who wrote it. An Executor line
on an overridden task still fails, because the lane gate excludes human
Rule S overrides.

## Why a script checks the plan

These rules used to be a checklist the planner ran against its own work, and a
planner grading itself passes what it meant rather than what it wrote.
`scripts/plan-lint` applies the same checks the same way whichever model wrote
the plan, and it reads `ladder.md`'s tables at run time, so the checks cannot
drift from the tables they enforce.
````

- [ ] **Step 3: session-budget.md**

Old:

````text
  subagent-driven-development (the final review runs in a fresh session).
  The plan-saved stop is not yet wired into `writing-plans` — invoking
  dr-superpowers:handoff there is a follow-up, not part of this release.
````

New:

````text
  subagent-driven-development (the final review runs in a fresh session).
  writing-plans runs dr-superpowers:handoff once the plan is reviewed.
````

- [ ] **Step 4: Verify**

Run:

```bash
f=plugins/dr-superpowers/skills/writing-plans/SKILL.md
grep -c '^## Contracts$\|^## Assumptions (evidence)$\|^## Task index$' "$f"
grep -nE 'Check your work|Which approach' "$f" || echo clean
grep -c 'plan-lint' plugins/dr-superpowers/skills/writing-plans/references/assigning-implementers.md
timeout 60 node scripts/validate-repository.mjs
```

Expected: `3`, `clean`, `3`, then the validator's success line.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/skills/writing-plans/references/assigning-implementers.md plugins/dr-superpowers/reference/session-budget.md
git commit -m "feat(superpowers): lint, review and hand off plans"
```

---

### Task 10: Entry point and brainstorming alignment

**Files:**
- Modify: `P/skills/using-superpowers/SKILL.md` (full replacement)
- Modify: `P/skills/brainstorming/SKILL.md`
- Test: `P/tests/hook.test.sh` (insert a block)

**Interfaces:**
- Consumes: the Process line vocabulary (Contracts).
- Produces: nothing new; the SessionStart hook injects this file unchanged.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

The entry point is injected into every session and shares the hook's 10,000-character cap with the compaction snapshot. It must not contain the string `dr-superpowers:using-superpowers` (the hook test counts that string exactly once in the injected context).

- [ ] **Step 1: Write the failing test**

In `P/tests/hook.test.sh`, insert this block immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# The entry point rides in every session's baseline and shares the hook's
# 10,000-character cap with the compaction snapshot.
check "entry point is at most 4,800 bytes" \
  "$([ "$(wc -c < "$HERE/../skills/using-superpowers/SKILL.md")" -le 4800 ] && echo yes || echo no)" "yes"

```

Run: `export TMPDIR="$(cygpath -m "$TMP")"; timeout 120 bash plugins/dr-superpowers/tests/hook.test.sh | tail -n 1`
Expected: `33 passed, 0 failed` — today's file is 4,078 bytes, so the new check already passes; it guards the rewrite.

- [ ] **Step 2: Replace the entry point**

Replace the whole of `P/skills/using-superpowers/SKILL.md` with:

`````markdown
---
name: using-superpowers
description: Use when starting any conversation - establishes how to find and use skills, requiring skill invocation before ANY response including clarifying questions
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>

## The Rule

If a skill might apply to what you are doing, invoke it before any response or action, clarifying questions and exploration included. Announce "Using [skill] to [purpose]" and follow it; if it has a checklist, create a todo per item. Before entering plan mode, brainstorm.

| Thought | Reality |
|---|---|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "Let me explore first" | Skills tell you how to explore. Check first. |
| "I remember this skill" | Skills evolve. Read the current version. |

## Routing

| When | Skill |
|---|---|
| Building or changing behaviour | dr-superpowers:brainstorming |
| A bug, failing test or surprise | dr-superpowers:systematic-debugging |
| An approach decision is open | dr-superpowers:selecting-approaches |
| A spec is approved | dr-superpowers:writing-plans |
| Executing a plan | the skill its `**Execution:**` line names: dr-superpowers:subagent-driven-development or dr-superpowers:executing-plans |
| Writing code | dr-superpowers:test-driven-development |
| Isolating work | dr-superpowers:using-git-worktrees |
| Before claiming done | dr-superpowers:verification-before-completion |
| Asking for or receiving review | dr-superpowers:requesting-code-review, dr-superpowers:receiving-code-review |
| Work complete | dr-superpowers:finishing-a-development-branch |
| Stopping mid-work, or picking it up | dr-superpowers:handoff, dr-superpowers:resume-execution |
| Writing a skill | dr-superpowers:writing-skills |

## Principles

- **Think before coding.** State assumptions. Ask only in design phases; during execution, rule and log the ruling.
- **Simplicity first.** The least code that meets the goal; no speculative abstraction.
- **Surgical changes.** Touch only what the task needs; report adjacent problems instead of fixing them.
- **Goal-driven.** Define a verifiable success check before you start, and run it before you claim done.

## Process Depth

Take the lightest path that fits. Write a spec and a plan only when a trigger holds: a new project or subsystem; an interface that something outside its own files depends on changes; the files touched cannot be enumerated after exploring; a load-bearing approach question is open; irreducible risk (security, data loss, migration, concurrency); behaviour too intricate for a chat design; or your human partner asked for a spec. State the choice in one line before acting, `Process: <spike|bounded|architectural>, <inline|subagent> — <trigger | no trigger>`, and still get approval. Execute inline by default when the plan allows it (every task scores 3 or less, none at risk 3). Bugs go to systematic-debugging first.

Prefer an indexed code tool (for example darkmem `code_search`) over Explore subagents when one is available.

## Session Budget

- `scripts/task-brief`, `scripts/review-package` and `scripts/context-size` print a budget line. `handoff` means: finish the step in flight, then use dr-superpowers:handoff. See [session-budget.md](../../reference/session-budget.md).
- Picking up earlier work: run `scripts/repo-audit` first; a plan with a ledger continues through dr-superpowers:resume-execution.
- After more than an hour idle, start fresh from `.superpowers/handoff/latest.md`: the prompt cache is cold.
- After compaction, trust the compaction snapshot, the ledger and `git log` over the summary.

## Platform and Precedence

- Codex: read `references/codex-tools.md`.
- User instructions (CLAUDE.md, AGENTS.md, direct requests) take precedence over skills, which override default behaviour.
`````

Run: `wc -c < plugins/dr-superpowers/skills/using-superpowers/SKILL.md`
Expected: under 4800 (about 3.9k).

- [ ] **Step 3: Align brainstorming with the trigger list**

In `P/skills/brainstorming/SKILL.md`:

Old:

````text
Before your first question, classify the request and say the
classification out loud — "this looks bounded, so I'll present a short
design here rather than write a spec" — so your human partner can
override it:
````

New:

````text
Before your first question, classify the request and say it in one
line — `Process: <spike|bounded|architectural>, <inline|subagent> —
<trigger | no trigger>` — so your human partner can override it. The
triggers are the seven in dr-superpowers:using-superpowers' Process Depth:
a new project or subsystem; an interface that something outside its own
files depends on changes; the files touched cannot be enumerated after
exploring; a load-bearing approach question is open; irreducible risk
(security, data loss, migration, concurrency); behaviour too intricate for
a chat design; or your human partner asked for a spec.
````

Old:

````text
- **Bounded** — a well-scoped change to code that already exists in
  this repo: a new flag, a small endpoint, a one-file fix.
  Understanding the kind of app is not enough — bounded means the flow
  you are changing is already here to read. If there is no existing
  flow to change, the task is not bounded. Ask the clarifying
````

New:

````text
- **Bounded** — no trigger holds: a new flag, a small endpoint, a
  one-file fix, or a small feature that adds a new flow. Ask the clarifying
````

Old:

````text
- **Architectural** — new projects, new subsystems, changes that
  restructure how components fit together or alter interfaces others
  depend on. Follow the full process: questions, approaches, sectioned
````

New:

````text
- **Architectural** — at least one trigger holds; name it. Follow the
  full process: questions, approaches, sectioned
````

Old:

````text
When in doubt between two paths, take the heavier one. The ratchet is
one-way: hidden complexity discovered mid-task upgrades the path —
stop, say so, and step up. Nothing downgrades mid-task.
````

New:

````text
Doubt means check the trigger list, not jump to the heavier path. The
ratchet is one-way: a trigger discovered mid-task upgrades the path —
stop, say so, and step up. Nothing downgrades mid-task.
````

Old:

````text
| "I'll call it bounded and skip the spec" | Reaching for a label to skip work IS the doubt — take the heavier path. |
````

New:

````text
| "I'll call it bounded and skip the spec" | Name, for each of the seven triggers, why it fails — or take the architectural path. |
````

Old:

````text
| "I understand this kind of app, so it's bounded" | Bounded measures the repo, not your familiarity. A new project has no existing flow — it is architectural. |
````

New:

````text
| "I understand this kind of app, so it's bounded" | Bounded is decided by the trigger list, not by familiarity. A new project is a trigger. |
````

- [ ] **Step 4: Verify**

Run:

```bash
export TMPDIR="$(cygpath -m "$TMP")"
timeout 120 bash plugins/dr-superpowers/tests/hook.test.sh | tail -n 1
grep -nE 'take the heavier one|no existing flow' plugins/dr-superpowers/skills/brainstorming/SKILL.md || echo clean
timeout 60 node scripts/validate-repository.mjs
```

Expected: `33 passed, 0 failed`, `clean`, then the validator's success line.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/using-superpowers/SKILL.md plugins/dr-superpowers/skills/brainstorming/SKILL.md plugins/dr-superpowers/tests/hook.test.sh
git commit -m "feat(superpowers): rewrite entry point, align triage"
```

---

### Task 11: Reinforcement blocks

**Files:**
- Modify: `P/skills/executing-plans/SKILL.md`
- Modify: `P/skills/test-driven-development/SKILL.md`
- Modify: `P/skills/systematic-debugging/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: executing-plans**

Old:

````text
Load plan, review critically, execute all tasks, report when complete.
````

New:

````text
Load plan, review critically, execute all tasks, report when complete.

**Surgical execution:** change only what the task names. Note adjacent
problems in the ledger as `Task <N>: minor (deferred): <one-liner>` instead of
fixing them, and write each assumption you make where the plan is silent to
the ledger as `Ruling: <assumption> — plan silent — <cost if wrong>`.
````

- [ ] **Step 2: test-driven-development**

Old:

````text
- Understand a dependency's side effects before mocking it
````

New:

````text
- Understand a dependency's side effects before mocking it

**The quality bar:** a test that still passes when the implementation returns
a constant (`return <constant>`), or when the implementation is deleted, is
invalid — it proves nothing. Before you rely on a test, name the constant or
the deletion that would make it fail.
````

Old:

````text
- Test passes immediately
````

New:

````text
- Test passes immediately
- Test still passes with `return <constant>`, or with the implementation deleted
````

- [ ] **Step 3: systematic-debugging**

Old:

````text
- **"One more fix attempt" (when already tried 2+)**
````

New:

````text
- **"One more fix attempt" (when already tried 2+) — a third attempt at the same fix means stop and question the assumption behind the first two**
- **The same test still failing after three edits**
````

Old:

````text
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question pattern, don't fix again. |
````

New:

````text
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question the assumption behind the fixes, don't fix again; as a subagent, report BLOCKED with what you tried. |
````

- [ ] **Step 4: Verify**

Run:

```bash
grep -c 'Surgical execution' plugins/dr-superpowers/skills/executing-plans/SKILL.md
grep -c 'return <constant>' plugins/dr-superpowers/skills/test-driven-development/SKILL.md
grep -c 'three edits' plugins/dr-superpowers/skills/systematic-debugging/SKILL.md
timeout 60 node scripts/validate-repository.mjs
```

Expected: `1`, `2`, `1`, then the validator's success line.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/executing-plans/SKILL.md plugins/dr-superpowers/skills/test-driven-development/SKILL.md plugins/dr-superpowers/skills/systematic-debugging/SKILL.md
git commit -m "feat(superpowers): add reinforcement blocks"
```

---

### Task 12: README, version 1.4.0, full verification

**Files:**
- Modify: `P/README.md`
- Modify: `P/.claude-plugin/plugin.json:5`, `P/.codex-plugin/plugin.json:3`

**Interfaces:**
- Consumes: everything above.
- Produces: version `1.4.0` on both manifests.

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: README edits**

Old:

````text
`scripts/sdd-workspace`, `task-brief`, `review-package`, `next-step`,
`context-size`, and `repo-audit` — `next-step` ends every session with its next
````

New:

````text
`scripts/sdd-workspace`, `task-brief`, `review-package`, `next-step`,
`context-size`, `repo-audit`, `plan-lint`, and `plan-amend` — `next-step` ends every session with its next
````

Old:

````text
## What a plan looks like
````

New:

````text
## What a plan looks like

A plan opens with a header block: Goal, Spec, the `**Execution:**` line that
decides inline or subagent execution, Global Constraints, Contracts (every name
one task produces and another consumes), Assumptions with evidence, and a Task
index. `scripts/plan-lint` checks it, and a judge reviews it against
`criteria/plan-review.md` before it is saved. Each task then reads:
````

Old:

````text
Edit the `**Implementer:**` line to override. `subagent-driven-development`
obeys the line and never recomputes when it is present.
````

New:

````text
Edit the `**Implementer:**` line to override. `subagent-driven-development`
obeys the line and never recomputes when it is present. Add
`**Override:** <reason>` below the Evaluation line so that `plan-lint` reports
the deviation as a warning instead of an error.
````

Old:

````text
   upstream's unmeasured sessions - see [Session budget](#session-budget).
````

New:

````text
   upstream's unmeasured sessions - see [Session budget](#session-budget).
9. **Small-model planning.** A strong model plans once; small models execute.
   Every task brief carries the header's Global Constraints and Contracts, the
   controller reads only the header and one brief at a time, and judgment
   calls go to a read-only ruling seat (`judge-fable`). Its plan corrections
   land in an append-only `amendments.md` through `scripts/plan-amend`; the
   plan file is never edited during execution.
````

Old:

````text
package, the five-round cap, the breaker and its adjudication rules, and the
````

New:

````text
package, the five-round cap, the breaker (whose adjudication now goes to the ruling seat), and the
````

Old:

````text
`criteria/` holds the verifier criteria, including `codex-review-schema.json`
for the risk-3 Codex seat;
````

New:

````text
`criteria/` holds the verifier criteria, including `plan-review.md` for plan
review and `codex-review-schema.json` for the risk-3 Codex seat;
````

- [ ] **Step 2: Version 1.4.0**

In `P/.claude-plugin/plugin.json` and `P/.codex-plugin/plugin.json`, change `"version": "1.3.0",` to `"version": "1.4.0",`.

Run: `grep -h '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json`
Expected: two lines, both `"version": "1.4.0",`.

- [ ] **Step 3: Full verification**

Run:

```bash
export TMPDIR="$(cygpath -m "$TMP")"
timeout 60 node scripts/validate-repository.mjs
timeout 1800 node scripts/test-all.mjs
```

Expected: the validator passes; `test-all.mjs` passes every suite except the known environmental `rg: command not found` failure in `tests/ui-discovery.test.mjs`. Any other failure is a defect: fix it before continuing.

Run:

```bash
timeout 120 claude plugin validate .
timeout 120 claude plugin validate plugins/dr-status
timeout 120 claude plugin validate plugins/dr-superpowers
timeout 120 claude plugin validate plugins/dcc-darkraise-ui
timeout 120 claude plugin validate plugins/dcc-darkraise-win32ui
```

Expected: every validation passes.

Confirm no process you started is still running (`test-all.mjs` kills its own children; check for stray `bash` or `node` you launched).

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
git commit -m "feat(superpowers)!: small-model planning, 1.4.0"
```

