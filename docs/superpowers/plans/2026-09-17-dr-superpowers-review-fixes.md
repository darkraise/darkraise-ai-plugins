# dr-superpowers Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship dr-superpowers 1.12.0: a working-directory contract with a same-repository check, delegation of total-4 tasks up to a third of a plan, named final-review seats, and escalation out of inline mode above both rungs.

**Architecture:** Two new `lib/plan.sh` functions (`plan_require_same_repo`, `plan_delegated`) feed the scripts that already share that library; `review-route` gains `--final` and `--final-fix`; the skills and references then name those outputs instead of prose rules. Every script change lands with its bash suite; every prose change lands with a text pin.

**Tech Stack:** Bash (Git Bash on Windows), awk, git; bash test suites under `plugins/dr-superpowers/tests/`; Node for repository validation.

**Spec:** `docs/superpowers/specs/2026-09-17-dr-superpowers-review-fixes-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — Tasks 1 and 6 are heavy (2 of 12) and delegated; the highest self-implemented total is 3 (impl-sonnet-high)

**Plan review:** 2026-09-17 — dr-superpowers:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 17 (round 2)

## Global Constraints

- Release version is `1.12.0` in both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json` (Task 12 only).
- Bash, awk, sed, git and jq only; no new dependencies. `rg` is not on PATH in Git Bash.
- Every test, script and CLI run is bounded by `timeout` (suites: `timeout 300`; `node scripts/test-all.mjs`: `timeout 900`, run alone).
- Run suites with `env -u CLAUDE_CONFIG_DIR` (it points at `~/.claude-alt` on this machine).
- Do not touch Codex-host routing or `plugins/dr-superpowers/reference/native-codex.md`.
- Never stage `plugins/darkmem-resume/` or `.superpowers/`. Stage by explicit path.
- Never stage a test script through `git update-index --cacheinfo`: it drops the exec bit. A new test script is staged with `git add` then `git update-index --chmod=+x <path>`.
- `plugins/dr-superpowers/skills/using-superpowers/SKILL.md` stays at or below 4800 bytes (`tests/hook.test.sh:124`).
- Inside test heredocs, fixture lines that begin with `**Files:**`, `**Implementer:**`, `**Evaluation:**`, `**Override:**` or `#### Part` carry a leading `|` stripped by `sed 's/^|//'`: `plan-lint` and `review-route` scan task text without skipping fences, so a plan quoting the suite must not see them.
- Commits: `<type>(superpowers): <subject>`, subject at most 50 characters, imperative, no period. English only.
- Keep a prose phrase that a test pins on one source line; a line break inside it breaks the `grep -F` pin.

## Contracts

- **`plan_require_same_repo FILE`** (`scripts/lib/plan.sh`, Task 1). Returns 0 when `git -C "$(dirname FILE)" rev-parse --show-toplevel` equals `git rev-parse --show-toplevel` in the working directory. Otherwise prints one line to stderr and exits 2. `<script>` is `basename "$0"`:
  - working directory outside a repository: `<script>: not inside a git repository`
  - otherwise: `<script>: <FILE> is in <plan top level>, but the working directory is in <cwd top level>; run from inside the plan's worktree`, where `<plan top level>` is `no git repository` when FILE's directory is outside one.
- **`tests/working-directory.test.sh`** (Task 1 creates it; Task 3 inserts checks above its last two lines, the summary `printf` and `[ "$fail" -eq 0 ]`).
- **The contract bullet** (Task 2): the first bullet of `skills/using-superpowers/SKILL.md` §Session Budget. Other prose cites it as the exact text `(see using-superpowers §Session Budget)` (Task 3).
- **`plan_delegated FILE`** (`scripts/lib/plan.sh`, Task 4). One line per delegated task, ascending: `N<TAB>heavy` or `N<TAB>total 4`. Heavy: highest total 5 or more, or highest risk 3. Four-band: not heavy, highest total exactly 4; listed only when `3 x (four-band count) <= N`, `N` being the number of task headings. Tasks without a parseable Evaluation line are never listed.
- **Dispatch lines** (`scripts/task-brief`, Task 6), inline Claude-host plans only:
  - a delegated task's brief, second line: `**Dispatch:** delegated — total <t>, risk <r>`
  - `task-brief --header`, appended last line: `**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4)` (reasons from `plan_delegated`, in its order)
- **`plan-lint` rule 5 messages** (Task 5), Claude host:
  - `NOTE header: delegated: Task 2 (heavy), Task 5 (total 4)`
  - `WARN header: Execution line is inline but <h> of <n> tasks are heavy`
  - `WARN header: Execution line is subagent but only <h> of <n> tasks are heavy`
  - `WARN header: subagent Execution line should be claude --model sonnet --effort high`
  - `ERROR header: inline execution needs --model sonnet or opus (model <m>)`
  - `ERROR header: inline execution with a self-implemented task at total 4 needs --model opus`
  - `ERROR header: inline execution needs --effort <required> or above (effort <e>)`
- **`review-route PLAN_FILE --final`** (Task 8) prints exactly one of:
  - `review-seat final primary=dr-superpowers:judge-fable fallback=dr-superpowers:judge-opus reason=intricate`
  - `review-seat final primary=dr-superpowers:judge-opus fallback=- reason=plain`
- **`review-route PLAN_FILE --final-fix FILE [FILE ...]`** (Task 9) prints `review-seat final-fix primary=dr-superpowers:<agent> fallback=- reason=tasks:<n>[,<n>...]`, or `review-seat final-fix primary=dr-superpowers:impl-sonnet-high fallback=- reason=floor` when no task matches.
- **Ledger line** (Task 10): `Final fix: implementer <agent> (assigned; base <sha7>)`.

## Assumptions (evidence)

- Codex is unusable this session: `bash scripts/codex-gate` printed `codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe` on 2026-09-17, so no task carries an `**Executor:**` line.
- Every line number below was re-located on 2026-09-17 against HEAD `3a1bc36` (after the 1.11.1 batch); Replace blocks quote the current text, so match text, not numbers.
- This plan is linted by the pre-change `plan-lint` (`scripts/plan-lint:259-289`), which requires `--model opus` only when a non-heavy task totals 4. No task here totals 4, so `sonnet` / `high` passes both the old and the new rule.
- `skills/using-superpowers/SKILL.md` is 4419 bytes (`wc -c`, 2026-09-17); Tasks 2 and 7 add about 190 bytes, under the 4800 cap.
- Existing suites survive Task 1: `tests/inline-mode.test.sh:194-214` passes an explicit OUTFILE to `task-brief`, so `sdd-workspace` is not called; `tests/plan-lint.test.sh` runs in a temporary directory that is not a repository and never calls `sdd-workspace`; `tests/next-step.test.sh:155-168` runs from the worktree with a relative plan path; `tests/next-step.test.sh:365` runs outside any repository and still exits 2; `tests/budget-line.test.sh:36` runs from the plan's repository.
- `scripts/plan-amend:21` calls `sdd-workspace` after `cd` to the plan's directory, so it always passes the check.
- Inference: `task-brief` with an explicit OUTFILE skips `sdd-workspace` and so skips the check. Spec §3.3 names inheritance through `sdd-workspace` only, so this plan leaves it.
- Ledger agent names appear with and without the `dr-superpowers:` prefix (`tests/next-step.test.sh:384` writes `impl-sonnet-low`), so `--final-fix` strips any prefix.
- The fix-round clauses `escalated <old> -> <new>` and `HANDBACK to <agent>` come from the ledger grammar (`skills/subagent-driven-development/SKILL.md:259-275`). The inline marker `Task <N>: escalated inline -> subagent` also matches `escalated X -> Y`, so `--final-fix` accepts only targets that begin `impl-`.
- A minimal plan with no Spec line works with `next-step` and `review-package`: both exited 0 on such a plan in a scratch repository on 2026-09-17.
- Ranks follow `reference/ladder.md` §Why this terminates: `impl-sonnet-high` is 12, `impl-opus-medium` 21, `impl-opus-high` 22.
- Spec §6 does not say how to walk from a session rung that is not an escalation-table source (an `xhigh` or `max` inline effort). Task 11 follows the spec's wording and adds no rule for it.
- If this plan executes in a linked worktree, the plugin root the session prints is the primary checkout's, so the scripts stay at their pre-change versions until merge. No task's brief depends on the new behaviour.
- `node scripts/test-all.mjs` takes over nine minutes and runs every `plugins/dr-superpowers/tests/*.test.sh` suite (`scripts/test-all.mjs:39`). Its one known failure is `tests/ui-discovery.test.mjs` (`bash: rg: command not found`), per the 1.11.1 batch's handoff (`.superpowers/handoff/latest.md`, 2026-09-17), so every dr-superpowers suite passed at `3a1bc36`. Not re-run while planning.
- `--final-fix` reads only `Task <N>:` ledger lines. An escalation recorded on a `Group <a>-<b>: review round` line is not read, so a batch-escalated task ranks at its assigned agent. Spec §5.2 names the task's assigned and fix-round lines only; batch escalations are out of scope.
- `--final-fix` strips a `:line-list` suffix as well as a `:line-range` one: this repository's plans write entries such as `plan-lint:143,239,259-289`.

## Task index

1. Refuse a plan from another checkout
2. State the working-directory contract
3. Point skill prose at the contract
4. Add plan_delegated
5. Rewrite plan-lint rule 5
6. Compute delegation reasons in task-brief
7. Document total-4 delegation
8. Route the final Claude review
9. Route the final fix wave
10. Name the final-review seats in the skills
11. Escalate out of inline mode above both rungs
12. Release 1.12.0

---

### Task 1: Refuse a plan from another checkout

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/plan.sh`
- Modify: `plugins/dr-superpowers/scripts/sdd-workspace`
- Modify: `plugins/dr-superpowers/scripts/review-package`
- Modify: `plugins/dr-superpowers/scripts/next-step`
- Test: `plugins/dr-superpowers/tests/working-directory.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `plan_require_same_repo FILE` and `tests/working-directory.test.sh` (Contracts).

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/working-directory.test.sh`:

```bash
#!/usr/bin/env bash
# Scripts find the repository from the working directory. A plan in another
# repository or worktree is refused before anything is written, so one plan's
# ledger, briefs and amendments never split across two checkouts.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../scripts"

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
unset CLAUDE_CONFIG_DIR
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

mkrepo() { # mkrepo <dir> — a repository with a committed one-task plan at docs/plan.md
  git init -q "$1"
  mkdir -p "$1/docs"
  printf '# Plan\n\n**Execution:** inline — `claude --model sonnet --effort low` — x\n\n## Task index\n\n1. Only\n\n### Task 1: Only\n\nBody.\n' > "$1/docs/plan.md"
  git -C "$1" add -A && git -C "$1" commit -qm plan
}
run() { # run <dir> <script> <args...>; sets out, err and status
  out=$(cd "$1" && bash "$S/$2" "${@:3}" 2>"$TMP/err"); status=$?
  err=$(cat "$TMP/err")
}
state() { # state <dir> — yes when a .superpowers directory exists there
  if [ -d "$1/.superpowers" ]; then echo yes; else echo no; fi
}

X="$TMP/x" Y="$TMP/y"
mkrepo "$X"
mkrepo "$Y"
XTOP=$(git -C "$X" rev-parse --show-toplevel)
YTOP=$(git -C "$Y" rev-parse --show-toplevel)
WANT="is in $XTOP, but the working directory is in $YTOP; run from inside the plan's worktree"

# --- a plan in another repository ---
run "$Y" sdd-workspace "$X/docs/plan.md"
check "sdd-workspace: another repository exits 2" "$status" "2"
check "sdd-workspace: names both top levels" "$err" "sdd-workspace: $X/docs/plan.md $WANT"
run "$Y" review-package "$X/docs/plan.md" HEAD HEAD
check "review-package: another repository exits 2" "$status" "2"
check "review-package: names both top levels" "$err" "review-package: $X/docs/plan.md $WANT"
run "$Y" task-brief "$X/docs/plan.md" 1
check "task-brief: inherits the refusal from sdd-workspace" "$status" "2"
run "$Y" next-step "$X/docs/plan.md"
check "next-step: another repository exits 2" "$status" "2"
has "next-step: names both top levels on stdout" "$out" "next-step: $X/docs/plan.md $WANT"
check "no state in the plan's repository" "$(state "$X")" "no"
check "no state in the working directory's repository" "$(state "$Y")" "no"

# --- a plan outside any repository, and a working directory outside one ---
printf '# Loose\n' > "$TMP/loose.md"
run "$X" sdd-workspace "$TMP/loose.md"
check "a plan outside any repository exits 2" "$status" "2"
check "a plan outside any repository is named" "$err" \
  "sdd-workspace: $TMP/loose.md is in no git repository, but the working directory is in $XTOP; run from inside the plan's worktree"
run "$TMP" sdd-workspace "$X/docs/plan.md"
check "a working directory outside any repository exits 2" "$status" "2"
check "a working directory outside any repository is named" "$err" "sdd-workspace: not inside a git repository"

# --- a linked worktree given its primary checkout's plan path ---
WT="$TMP/wt"
git -C "$X" worktree add -q -b wt "$WT"
WTTOP=$(git -C "$WT" rev-parse --show-toplevel)
run "$WT" sdd-workspace "$X/docs/plan.md"
check "worktree: the primary checkout's plan exits 2" "$status" "2"
check "worktree: names both top levels" "$err" \
  "sdd-workspace: $X/docs/plan.md is in $XTOP, but the working directory is in $WTTOP; run from inside the plan's worktree"
check "worktree: no state in the worktree" "$(state "$WT")" "no"
check "worktree: no state in the primary checkout" "$(state "$X")" "no"
run "$WT" sdd-workspace docs/plan.md
check "worktree: its own plan passes" "$status" "0"
has "worktree: the workspace is in the worktree" "$out" "/wt/.superpowers/sdd/plan"
git -C "$X" worktree remove --force "$WT" >/dev/null 2>&1

# --- the same repository keeps working ---
run "$X" sdd-workspace docs/plan.md
check "same repository: sdd-workspace exits 0" "$status" "0"
run "$X/docs" sdd-workspace plan.md
check "a relative plan resolves against the working directory" "$status" "0"
run "$X" sdd-workspace "$X/docs/plan.md"
check "same repository: an absolute plan path passes" "$status" "0"
run "$X" review-package docs/plan.md HEAD HEAD
check "same repository: review-package exits 0" "$status" "0"
run "$X" next-step docs/plan.md
check "same repository: next-step exits 0" "$status" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/working-directory.test.sh`
Expected: FAIL on every "exits 2" check for another repository and the worktree (the scripts exit 0 and create `.superpowers/`); the same-repository checks pass.

- [ ] **Step 3: Add `plan_require_same_repo` to the library**

Append to the end of `plugins/dr-superpowers/scripts/lib/plan.sh`:

```bash

# plan_require_same_repo FILE — return when FILE's directory and the working
# directory share a top level; otherwise name both on stderr and exit 2.
# Scripts find the repository from the working directory, but
# plan_amendments_file and plan_ledger resolve from the plan's directory, so a
# plan in another checkout would split one plan's state across two. A linked
# worktree and its primary checkout have different top levels, so a worktree
# session given the primary checkout's plan path is refused as well.
plan_require_same_repo() {
  local me cwd_top plan_top
  me=$(basename "$0")
  cwd_top=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { printf '%s: not inside a git repository\n' "$me" >&2; exit 2; }
  plan_top=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) \
    || plan_top="no git repository"
  [ "$plan_top" != "$cwd_top" ] || return 0
  printf "%s: %s is in %s, but the working directory is in %s; run from inside the plan's worktree\n" \
    "$me" "$1" "$plan_top" "$cwd_top" >&2
  exit 2
}
```

- [ ] **Step 4: Call it from `sdd-workspace`**

In `plugins/dr-superpowers/scripts/sdd-workspace`, replace:

````text
set -euo pipefail

if [ $# -ne 1 ]; then
````

with:

````text
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib/plan.sh"

if [ $# -ne 1 ]; then
````

and replace:

````text
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

slug=$(basename "$plan" .md)
````

with:

````text
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
plan_require_same_repo "$plan"

slug=$(basename "$plan" .md)
````

- [ ] **Step 5: Call it from `review-package`**

In `plugins/dr-superpowers/scripts/review-package`, replace:

````text
set -euo pipefail

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
````

with:

````text
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib/plan.sh"

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
````

and replace:

````text
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

git rev-parse --verify --quiet "$base" >/dev/null || { echo "bad BASE: $base" >&2; exit 2; }
````

with:

````text
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
plan_require_same_repo "$plan"

git rev-parse --verify --quiet "$base" >/dev/null || { echo "bad BASE: $base" >&2; exit 2; }
````

- [ ] **Step 6: Call it from `next-step`**

`next-step` prints every failure on stdout as well as stderr through `fail`, so it captures the message in a subshell (where `exit 2` ends only the subshell). In `plugins/dr-superpowers/scripts/next-step`, replace:

````text
[ -f "$plan" ] || fail 2 "no such file: $plan — run it from the repository root, or check the plan path"
````

with:

````text
[ -f "$plan" ] || fail 2 "no such file: $plan — run it from the repository root, or check the plan path"
repo_err=$(plan_require_same_repo "$plan" 2>&1) || fail 2 "${repo_err#next-step: }"
````

- [ ] **Step 7: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/working-directory.test.sh`
Expected: PASS, `0 failed`.

Run each of these, one at a time: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/<suite>.test.sh` for `next-step`, `budget-line`, `inline-mode`, `plan-amend`, `project-status`, `repo-audit`.
Expected: each ends `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/scripts/sdd-workspace \
  plugins/dr-superpowers/scripts/review-package plugins/dr-superpowers/scripts/next-step \
  plugins/dr-superpowers/tests/working-directory.test.sh
git update-index --chmod=+x plugins/dr-superpowers/tests/working-directory.test.sh
git ls-files -s plugins/dr-superpowers/tests/working-directory.test.sh   # expect mode 100755
git commit -m "fix(superpowers): refuse a plan from another checkout"
```

### Task 2: State the working-directory contract

**Files:**
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`
- Modify: `plugins/dr-superpowers/scripts/session-start.sh`
- Test: `plugins/dr-superpowers/tests/hook.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the contract bullet (Contracts).

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/hook.test.sh`, replace:

````text
check "well-formed: names the plugin root" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c 'Plugin root (run every')" "1"
````

with:

````text
check "well-formed: names the plugin root" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c '^Plugin root: ')" "1"
check "well-formed: the plugin root line states the working-directory contract" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c ' — call scripts by this path, with the working directory inside the project$')" "1"
check "using-superpowers states the working-directory contract" \
  "$(grep -cF "with the working directory inside the project's worktree" "$HERE/../skills/using-superpowers/SKILL.md")" "1"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/hook.test.sh`
Expected: FAIL on the three checks above.

- [ ] **Step 3: Change the entry-point line**

In `plugins/dr-superpowers/scripts/session-start.sh`, replace:

````text
# The skills say "from the plugin root"; this line is where the root is named.
````

with:

````text
# Skills call scripts by the plugin-root path with the working directory inside
# the project; this line is where the root is named.
````

and replace:

````text
Plugin root (run every \`scripts/…\` command from here): $(escape_for_json "$plugin_root_shown")
````

with:

````text
Plugin root: $(escape_for_json "$plugin_root_shown") — call scripts by this path, with the working directory inside the project
````

- [ ] **Step 4: State the contract in using-superpowers**

In `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`, replace:

````text
- Every `scripts/…` command runs from the plugin root, the path printed under this entry point (on Codex: the directory two levels above any skill file).
````

with:

````text
- Call every `scripts/…` command as `bash <plugin-root>/scripts/<name>`, with the working directory inside the project's worktree; a relative `PLAN_FILE` resolves against it. The plugin root is printed under this entry point (on Codex: the directory two levels above any skill file).
````

- [ ] **Step 5: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/hook.test.sh`
Expected: PASS, `0 failed` (the 4800-byte cap check included).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/using-superpowers/SKILL.md \
  plugins/dr-superpowers/scripts/session-start.sh plugins/dr-superpowers/tests/hook.test.sh
git commit -m "docs(superpowers): state the working-directory contract"
```

### Task 3: Point skill prose at the contract

**Files:**
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md:14-15,88,105-106,128`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md:14-15,74-75,173-174,202`
- Modify: `plugins/dr-superpowers/skills/handoff/SKILL.md:66-67`
- Modify: `plugins/dr-superpowers/skills/resume-execution/SKILL.md:16-17`
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md:283-284`
- Modify: `plugins/dr-superpowers/skills/project-status/SKILL.md:17-19`
- Modify: `plugins/dr-superpowers/skills/brainstorming/SKILL.md:237-238`
- Modify: `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md:286-287`
- Modify: `plugins/dr-superpowers/reference/delegated-task.md:55-56,145-146`
- Modify: `plugins/dr-superpowers/scripts/lib/snapshot.sh:92-94`
- Modify: `plugins/dr-superpowers/scripts/lib/codex-session.sh:4-6`
- Modify: `plugins/dr-superpowers/scripts/codex-plugin:30-32`
- Test: `plugins/dr-superpowers/tests/working-directory.test.sh`

**Interfaces:**
- Consumes: the contract bullet (Task 2); `tests/working-directory.test.sh` (Task 1).
- Produces: nothing later tasks use.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/working-directory.test.sh`, insert above the final two lines (`printf '\n%d passed, %d failed\n' "$pass" "$fail"` and `[ "$fail" -eq 0 ]`):

```bash
# --- the prose names one contract ---
P="$HERE/.."
check "no skill, reference or script says 'from the plugin root'" \
  "$(grep -rlF 'from the plugin root' "$P/skills" "$P/reference" "$P/scripts" 2>/dev/null)" ""
check "no skill or reference re-explains where the plugin root is" \
  "$(grep -rlF "the path the session's entry point names" "$P/skills" "$P/reference" 2>/dev/null)" ""
check "the compaction snapshot names the contract" \
  "$(grep -cF 'plugin-root path, with the working directory inside the project;' "$P/scripts/lib/snapshot.sh")" "1"
check "nine skill and reference files cite the contract" \
  "$(grep -rlF '(see using-superpowers §Session Budget)' "$P/skills" "$P/reference" | wc -l | tr -d ' ')" "9"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/working-directory.test.sh`
Expected: FAIL on the four checks above.

- [ ] **Step 3: Replace the parenthetical at each site**

Make each replacement exactly; every Replace text is unique in its file.

`plugins/dr-superpowers/skills/executing-plans/SKILL.md` and `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (the same text in both files), replace:

````text
1. Run `scripts/sdd-workspace PLAN_FILE`, from the plugin root (the path the session's entry point names; two
   levels above this skill's directory), and read `progress.md` and `handoff.md` in
````

with:

````text
1. Run `scripts/sdd-workspace PLAN_FILE` (see using-superpowers §Session Budget),
   and read `progress.md` and `handoff.md` in
````

`plugins/dr-superpowers/skills/executing-plans/SKILL.md`, replace:

````text
`scripts/next-step PLAN_FILE`, from the plugin root, as your last action. The
````

with:

````text
`scripts/next-step PLAN_FILE` (see using-superpowers §Session Budget) as your last action. The
````

`plugins/dr-superpowers/skills/executing-plans/SKILL.md`, replace:

````text
- Each plan owns a workspace: run `scripts/sdd-workspace PLAN_FILE`, from the
  plugin root, and it prints the plan's git-ignored directory
````

with:

````text
- Each plan owns a workspace: run `scripts/sdd-workspace PLAN_FILE`
  (see using-superpowers §Session Budget), and it prints the plan's git-ignored directory
````

`plugins/dr-superpowers/skills/executing-plans/SKILL.md` and `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (the same text in both files), replace:

````text
`scripts/task-brief --header PLAN_FILE`, from the plugin root, and read the
````

with:

````text
`scripts/task-brief --header PLAN_FILE` (see using-superpowers §Session Budget), and read the
````

`plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace:

````text
your human partner asking you to stop — run `scripts/next-step PLAN_FILE`,
from the plugin root (the path the session's entry point names; two levels above this skill's directory), as your last
action.
````

with:

````text
your human partner asking you to stop — run `scripts/next-step PLAN_FILE`
(see using-superpowers §Session Budget) as your last
action.
````

`plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace:

````text
  `scripts/sdd-workspace PLAN_FILE`, from the plugin root (the path the session's entry point names; two
  levels above this skill's directory) — it prints the plan's git-ignored
````

with:

````text
  `scripts/sdd-workspace PLAN_FILE` (see using-superpowers §Session Budget) — it prints the plan's git-ignored
````

`plugins/dr-superpowers/skills/handoff/SKILL.md`, replace:

````text
4. **Run `scripts/next-step`**, from the plugin root (the path the session's entry point
   names; two levels above this skill's directory):
````

with:

````text
4. **Run `scripts/next-step`** (see using-superpowers §Session Budget):
````

`plugins/dr-superpowers/skills/resume-execution/SKILL.md`, replace:

````text
1. **Orient in one call.** Run `scripts/repo-audit`, from the plugin root (the path the session's entry point names; two
   levels above this skill's directory). Read
````

with:

````text
1. **Orient in one call.** Run `scripts/repo-audit` (see using-superpowers §Session Budget). Read
````

`plugins/dr-superpowers/skills/writing-plans/SKILL.md`, replace:

````text
1. **Lint.** Run `scripts/plan-lint PLAN_FILE`, from the plugin root (the path the session's entry point names; two
   levels above this skill's directory), until it reports `0 errors`. Fix each
````

with:

````text
1. **Lint.** Run `scripts/plan-lint PLAN_FILE` (see using-superpowers §Session Budget)
   until it reports `0 errors`. Fix each
````

`plugins/dr-superpowers/skills/project-status/SKILL.md`, replace:

````text
1. **Orient in one call.** Run `scripts/repo-audit`, from the plugin root (the
   path the session's entry point names; two levels above this skill's
   directory). It gives branch and HEAD, worktrees, dirty files, plans with
````

with:

````text
1. **Orient in one call.** Run `scripts/repo-audit`
   (see using-superpowers §Session Budget). It gives branch and HEAD, worktrees, dirty files, plans with
````

`plugins/dr-superpowers/skills/brainstorming/SKILL.md`, replace:

````text
- Run `scripts/context-size`, from the plugin root (the path the session's entry point
  names; two levels above this skill's directory). On exit 5 (handoff), invoke dr-superpowers:handoff with
````

with:

````text
- Run `scripts/context-size` (see using-superpowers §Session Budget).
  On exit 5 (handoff), invoke dr-superpowers:handoff with
````

`plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md`, replace:

````text
If this work came from a plan file, run `scripts/next-step --complete PLAN_FILE`,
from the plugin root (the path the session's entry point names; two levels above this skill's directory), with the
````

with:

````text
If this work came from a plan file, run `scripts/next-step --complete PLAN_FILE`
(see using-superpowers §Session Budget), with the
````

`plugins/dr-superpowers/reference/delegated-task.md`, replace:

````text
- **Task brief:** run `scripts/task-brief PLAN_FILE N`, from the plugin root
  (the path the session's entry point names) — it extracts the task's full text
````

with:

````text
- **Task brief:** run `scripts/task-brief PLAN_FILE N`
  (see using-superpowers §Session Budget) — it extracts the task's full text
````

`plugins/dr-superpowers/reference/delegated-task.md`, replace:

````text
  `scripts/review-package PLAN_FILE BASE HEAD`, from the plugin root
  (the path the session's entry point names), and pass the reviewer the
````

with:

````text
  `scripts/review-package PLAN_FILE BASE HEAD`
  (see using-superpowers §Session Budget), and pass the reviewer the
````

- [ ] **Step 4: Update the compaction snapshot and the session-state comment**

`plugins/dr-superpowers/scripts/lib/snapshot.sh`, replace:

````text
over the summary above. If anything is unclear, run `scripts/repo-audit` from the
dr-superpowers plugin root; if the next budget line says `handoff`, run the
dr-superpowers handoff skill.'
````

with:

````text
over the summary above. If anything is unclear, run `scripts/repo-audit` by its
dr-superpowers plugin-root path, with the working directory inside the project;
if the next budget line says `handoff`, run the dr-superpowers handoff skill.'
````

`plugins/dr-superpowers/scripts/lib/codex-session.sh`, replace:

````text
# The file is keyed by session id rather than kept in the project: skills run
# these scripts from the plugin root, which for an installed plugin is not the
# project, and a quota is account-wide anyway. Readers fail closed - any state
````

with:

````text
# The file is keyed by session id rather than kept in the project: a quota is
# account-wide, so the answer belongs to the session, not to any one project
# the session works in. Readers fail closed - any state
````

`plugins/dr-superpowers/scripts/codex-plugin` (a comment only; the settings lookup is unchanged), replace:

````text
# User, then project, then local settings; the last file that defines the key
# wins. Scripts run from the plugin root, which is not the project, so project
# settings are read only when Claude Code names the project directory.
````

with:

````text
# User, then project, then local settings; the last file that defines the key
# wins. Project settings are read only when Claude Code names the project
# directory, never guessed from the working directory.
````

- [ ] **Step 5: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/working-directory.test.sh`
Expected: PASS, `0 failed`.

Run, one at a time with `env -u CLAUDE_CONFIG_DIR timeout 300 bash`: `plugins/dr-superpowers/tests/snapshot.test.sh`, `plugins/dr-superpowers/tests/hook.test.sh`, `plugins/dr-superpowers/tests/inline-mode.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`.
Expected: each ends `0 failed`.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/executing-plans/SKILL.md \
  plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md \
  plugins/dr-superpowers/skills/handoff/SKILL.md plugins/dr-superpowers/skills/resume-execution/SKILL.md \
  plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/skills/project-status/SKILL.md \
  plugins/dr-superpowers/skills/brainstorming/SKILL.md \
  plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md \
  plugins/dr-superpowers/reference/delegated-task.md plugins/dr-superpowers/scripts/lib/snapshot.sh \
  plugins/dr-superpowers/scripts/lib/codex-session.sh plugins/dr-superpowers/scripts/codex-plugin \
  plugins/dr-superpowers/tests/working-directory.test.sh
git commit -m "docs(superpowers): point script calls at the contract"
```

### Task 4: Add plan_delegated

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/plan.sh:147-151`
- Test: `plugins/dr-superpowers/tests/plan-lib.test.sh:161-163`

**Interfaces:**
- Consumes: `plan_scores` and `plan_tasks` (existing, `scripts/lib/plan.sh:35-47,124-145`).
- Produces: `plan_delegated FILE` (Contracts).

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/plan-lib.test.sh`, replace:

````text
sed 's/$/\r/' "$TMP/scores.md" > "$TMP/scores-crlf.md"
check "plan_scores: CRLF" "$(plan_scores "$TMP/scores-crlf.md" | tr '\t\n' ' |')" "1 1 0|2 5 2|3 4 3|4 - -|5 ? ?|"
````

with:

````text
sed 's/$/\r/' "$TMP/scores.md" > "$TMP/scores-crlf.md"
check "plan_scores: CRLF" "$(plan_scores "$TMP/scores-crlf.md" | tr '\t\n' ' |')" "1 1 0|2 5 2|3 4 3|4 - -|5 ? ?|"

# --- plan_delegated: heavy tasks, and total-4 tasks while a third or fewer ---
deleg_plan() { # deleg_plan <file> <total/risk ...> — one task per argument
  local f=$1 i=0 tr; shift
  printf '# Delegation\n' > "$f"
  for tr in "$@"; do
    i=$((i + 1))
    printf '\n### Task %s: t\n\n**Evaluation:** files 0 - spec 0 - coupling %s - risk %s = %s\n' \
      "$i" "$((${tr%/*} - ${tr#*/}))" "${tr#*/}" "${tr%/*}" >> "$f"
  done
}
deleg() { plan_delegated "$1" | tr '\t\n' ' |'; }
deleg_plan "$TMP/d1.md" 1/0 4/2 1/0 1/0 1/0 1/0
check "plan_delegated: one total-4 task in six" "$(deleg "$TMP/d1.md")" "2 total 4|"
deleg_plan "$TMP/d2.md" 4/2 1/0 4/2 1/0 1/0 1/0
check "plan_delegated: two total-4 tasks in six" "$(deleg "$TMP/d2.md")" "1 total 4|3 total 4|"
deleg_plan "$TMP/d3.md" 4/2 4/2 4/2 1/0 1/0 1/0
check "plan_delegated: three total-4 tasks in six are none" "$(deleg "$TMP/d3.md")" ""
deleg_plan "$TMP/d4.md" 5/2 4/2 1/0 4/3 1/0 1/0
check "plan_delegated: heavy and total-4 tasks together" "$(deleg "$TMP/d4.md")" "1 heavy|2 total 4|4 heavy|"
deleg_plan "$TMP/d5.md" 5/2 4/2 4/2 1/0
check "plan_delegated: heavy tasks stay when total-4 tasks pass a third" "$(deleg "$TMP/d5.md")" "1 heavy|"
sed 's/^|//' > "$TMP/d6.md" <<'EOF'
|# Split
|
|### Task 1: light
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: split
|
|#### Part A: small
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: larger
|
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
|
|### Task 3: unscored
EOF
check "plan_delegated: a split task with a total-4 part" "$(deleg "$TMP/d6.md")" "2 total 4|"
check "plan_delegated: the scores fixture" "$(deleg "$TMP/scores.md")" "2 heavy|3 heavy|"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/plan-lib.test.sh`
Expected: FAIL on the `plan_delegated` checks with `plan_delegated: command not found` on stderr.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/plan.sh`, directly after the `plan_heavy` function (its closing `}`), insert:

```bash

# plan_delegated FILE — the tasks an inline plan delegates, one "N<TAB>heavy"
# or "N<TAB>total 4" line each, ascending. Heavy tasks always. Tasks whose
# highest total is exactly 4 only while they are a third of the plan or fewer:
# past that, one Opus session costs less than a seat for each of them.
plan_delegated() {
  local tasks
  tasks=$(plan_tasks "$1" | grep -c . || true)
  plan_scores "$1" | awk -F'\t' -v n="$tasks" '
    $2 == "-" || $2 == "?" { next }
    $2 + 0 >= 5 || $3 + 0 == 3 { row[++k] = $1 "\theavy"; next }
    $2 + 0 == 4 { row[++k] = $1 "\ttotal 4"; four++ }
    END {
      for (i = 1; i <= k; i++)
        if (row[i] !~ /\ttotal 4$/ || 3 * four <= n + 0) print row[i]
    }
  '
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/plan-lib.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/tests/plan-lib.test.sh
git commit -m "feat(superpowers): add plan_delegated"
```

### Task 5: Rewrite plan-lint rule 5

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint:143,239,259-289`
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh:207-244`

**Interfaces:**
- Consumes: `plan_delegated FILE` (Contracts, Task 4).
- Produces: the `plan-lint` rule 5 messages (Contracts).

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Update the existing rule-5 cases and write the new ones**

In `plugins/dr-superpowers/tests/plan-lint.test.sh`, make these replacements.

Replace:

````text
has "inline at total 4 needs opus" "$out" "ERROR header: inline execution with a task at total 4 needs --model opus (highest total 4)"
````

with:

````text
has "inline at total 4 needs opus" "$out" "ERROR header: inline execution with a self-implemented task at total 4 needs --model opus"
````

Replace:

````text
has "inline that delegates needs effort high" "$out" "ERROR header: inline execution that delegates needs --effort high or above (effort low)"
lacks "a heavy minority no longer breaks inline" "$out" "inline execution needs every task"
has "inline names the delegated task" "$out" "NOTE header: delegated: Task 2"
````

with:

````text
has "inline that delegates needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort low)"
lacks "a heavy minority no longer breaks inline" "$out" "inline execution needs every task"
has "inline names the delegated task" "$out" "NOTE header: delegated: Task 2 (heavy)"
````

Replace:

````text
has "risk 3 is delegated" "$out" "NOTE header: delegated: Task 2"
has "risk 3 inline needs effort high" "$out" "ERROR header: inline execution that delegates needs --effort high or above (effort low)"
````

with:

````text
has "risk 3 is delegated" "$out" "NOTE header: delegated: Task 2 (heavy)"
has "risk 3 inline needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort low)"
````

Replace:

````text
has "a split task is heavy when one part is" "$out" "NOTE header: delegated: Task 2"
````

with:

````text
has "a split task is heavy when one part is" "$out" "NOTE header: delegated: Task 2 (heavy)"
````

Then find the line `lacks "a Codex-host plan gets no delegation note" "$out" "NOTE header"` and insert directly below it:

```bash

# --- R5 delegation: heavy tasks, and total-4 tasks while a third or fewer ---
ev() { # ev <total> — "<agent> <evaluation>" for a lint-clean task at that total
  case $1 in
    0) echo 'impl-haiku files 0 - spec 0 - coupling 0 - risk 0 = 0' ;;
    1) echo 'impl-sonnet-low files 0 - spec 0 - coupling 1 - risk 0 = 1' ;;
    2) echo 'impl-sonnet-medium files 0 - spec 1 - coupling 1 - risk 0 = 2' ;;
    3) echo 'impl-sonnet-high files 1 - spec 1 - coupling 1 - risk 0 = 3' ;;
    4) echo 'impl-opus-low files 0 - spec 1 - coupling 1 - risk 2 = 4' ;;
    5) echo 'impl-opus-medium files 1 - spec 1 - coupling 1 - risk 2 = 5' ;;
  esac
}
tplan() { # tplan <file> <mode> <model> <effort> <total ...> — one clean task per total
  local f=$1 mode=$2 model=$3 effort=$4 i=0 t e; shift 4
  {
    printf '# Mode Plan\n\n**Goal:** Demo.\n\n**Spec:** `docs/spec.md`\n\n'
    printf '**Execution:** %s — `claude --model %s --effort %s` — x\n\n' "$mode" "$model" "$effort"
    printf '**Plan review:** 2026-09-17 — dr-superpowers:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)\n\n'
    printf '## Global Constraints\n\n- Bash only.\n\n## Contracts\n\nNone\n\n## Assumptions (evidence)\n\n- None.\n\n## Task index\n\n'
    for t in "$@"; do i=$((i + 1)); printf '%s. Step %s\n' "$i" "$i"; done
    i=0
    for t in "$@"; do
      i=$((i + 1)); e=$(ev "$t")
      printf '\n### Task %s: Step %s\n\n**Files:**\n- Modify: `f%s.txt`\n\n**Implementer:** dr-superpowers:%s\n**Evaluation:** %s\n' \
        "$i" "$i" "$i" "${e%% *}" "${e#* }"
    done
  } > "$f"
}
tplan r1.md inline sonnet high 1 4 1 1 1 1
lint r1.md
check "one total-4 task in six on sonnet high: exit 0" "$status" "0"
has "one total-4 task in six is delegated" "$out" "NOTE header: delegated: Task 2 (total 4)"
lacks "a delegated total-4 task needs no Opus session" "$out" "needs --model opus"
tplan r2.md inline sonnet high 4 1 4 1 1 1
lint r2.md
check "two total-4 tasks in six on sonnet high: exit 0" "$status" "0"
has "two total-4 tasks in six are delegated" "$out" "NOTE header: delegated: Task 1 (total 4), Task 3 (total 4)"
tplan r3.md inline sonnet high 4 4 4 1 1 1
lint r3.md
lacks "three total-4 tasks in six are not delegated" "$out" "NOTE header"
has "a self-implemented total 4 needs Opus" "$out" "ERROR header: inline execution with a self-implemented task at total 4 needs --model opus"
tplan r4.md inline opus low 4 4 4 1 1 1
lint r4.md
check "three total-4 tasks in six on opus low: exit 0" "$status" "0"
tplan r5.md inline sonnet high 5 4 1 1 1 1
lint r5.md
check "a heavy and a total-4 task on sonnet high: exit 0" "$status" "0"
has "heavy and total-4 reasons together" "$out" "NOTE header: delegated: Task 1 (heavy), Task 2 (total 4)"
tplan r6.md inline sonnet medium 1 4 1 1 1 1
lint r6.md
has "delegating a total-4 task raises the effort to high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
tplan r7.md inline sonnet max 1 4 1 1 1 1
lint r7.md
check "an effort above the required one: exit 0" "$status" "0"
tplan r8.md inline sonnet medium 3 1 1 1 1 1
lint r8.md
has "a self-implemented total 3 needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
tplan r9.md inline sonnet low 2 1 1 1 1 1
lint r9.md
has "a self-implemented total 2 needs effort medium" "$out" "ERROR header: inline execution needs --effort medium or above (effort low)"
tplan r10.md inline sonnet low 0 0 0 0 0 0
lint r10.md
check "impl-haiku counts as low: exit 0" "$status" "0"
tplan r11.md inline haiku low 1 1
lint r11.md
has "inline on haiku is a model error" "$out" "ERROR header: inline execution needs --model sonnet or opus (model haiku)"
tplan r12.md inline fable high 1 1
lint r12.md
has "inline on fable is a model error" "$out" "ERROR header: inline execution needs --model sonnet or opus (model fable)"
tplan r13.md inline claude-opus-5 low 4 4 4 1 1 1
lint r13.md
lacks "a claude-opus model id counts as opus" "$out" "needs --model"
tplan r14.md inline claude-haiku-4-5 low 1 1
lint r14.md
has "a model id naming neither family is a model error" "$out" "ERROR header: inline execution needs --model sonnet or opus (model claude-haiku-4-5)"
tplan r15.md subagent opus high 5 5 5 5 1 1
lint r15.md
has "a subagent line at opus warns" "$out" "WARN header: subagent Execution line should be claude --model sonnet --effort high"
lacks "a heavy majority on subagent is not disputed" "$out" "Execution line is subagent but"
tplan r16.md subagent sonnet high 5 5 5 5 1 1
lint r16.md
lacks "a subagent line at sonnet high does not warn" "$out" "subagent Execution line should be"
tplan r17.md inline opus low 1 1 1 1 1 1
lint r17.md
check "opus where sonnet would do: exit 0" "$status" "0"
tplan r18.md subagent sonnet high 1 4 4 1 1 1
lint r18.md
has "total-4 tasks never count toward subagent mode" "$out" "WARN header: Execution line is subagent but only 0 of 6 tasks are heavy"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh`
Expected: FAIL on the updated message checks and on most `r1`-`r18` cases (the old rule prints `that delegates` and bare `Task 2` notes, and has no model, subagent-tier or non-delegating effort checks).

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/plan-lint`, replace:

````text
r5_bad="" max_total=0 lane="" units=""
````

with:

````text
r5_bad="" max_total=0 lane=""
````

Delete this line (inside the per-task loop):

````text
  units="$units$n $((a + b + c + d)) $d"$'\n'
````

Replace the whole R5 block, from the line `# R5: execution mode. A Codex-host plan keeps the all-or-nothing inline rule.` through the `fi` directly above `cat "$findings"`, with:

```bash
# R5: execution mode. A Codex-host plan keeps the all-or-nothing inline rule.
# On Claude, plan_delegated names the tasks an inline plan delegates, and heavy
# tasks alone decide whole-plan subagent mode. The inline model and effort
# follow the tasks the session implements itself, and a session that delegates
# runs the review loop, so its effort is at least high.
effort_rank() { case $1 in low) echo 0 ;; medium) echo 1 ;; high) echo 2 ;; xhigh) echo 3 ;; *) echo 4 ;; esac; }
if [ "$codex" -eq 1 ]; then
  if [ "$mode" = inline ] && [ -n "$r5_bad" ]; then
    say ERROR header "inline execution needs every task at total <= 4 and risk < 3; fails on Task${r5_bad}"
  fi
elif [ -n "$mode" ]; then
  delegated=$(plan_delegated "$src")
  task_count=$(grep -c . <<<"$nums" || true)
  heavy_count=$(grep -c $'\theavy$' <<<"$delegated" || true)
  if [ "$mode" = inline ] && [ $((2 * heavy_count)) -gt "$task_count" ]; then
    say WARN header "Execution line is inline but $heavy_count of $task_count tasks are heavy"
  elif [ "$mode" = subagent ] && [ $((2 * heavy_count)) -le "$task_count" ]; then
    say WARN header "Execution line is subagent but only $heavy_count of $task_count tasks are heavy"
  fi
  family=$exec_model
  case $exec_model in claude-*opus*) family=opus ;; claude-*sonnet*) family=sonnet ;; esac
  if [ "$mode" = subagent ]; then
    { [ "$family" = sonnet ] && [ "$exec_effort" = high ]; } \
      || say WARN header "subagent Execution line should be claude --model sonnet --effort high"
  else
    [ -z "$delegated" ] \
      || say NOTE header "delegated: $(awk -F'\t' '{ printf "%sTask %s (%s)", (NR > 1 ? ", " : ""), $1, $2 }' <<<"$delegated")"
    self_max=$(plan_scores "$src" | awk -F'\t' -v d=" $(cut -f1 <<<"$delegated" | tr '\n' ' ')" '
      $2 ~ /^[0-9]+$/ && index(d, " " $1 " ") == 0 && $2 + 0 > m { m = $2 + 0 }
      END { print m + 0 }')
    need=$(awk -v t="$self_max" '$1 == t { print $2 }' <<<"$assignment")
    need=${need##*-}
    case $need in low|medium|high) ;; *) need=low ;; esac
    [ -z "$delegated" ] || need=high
    if [ "$family" != sonnet ] && [ "$family" != opus ]; then
      say ERROR header "inline execution needs --model sonnet or opus (model $exec_model)"
    elif [ "$self_max" -eq 4 ] && [ "$family" != opus ]; then
      say ERROR header "inline execution with a self-implemented task at total 4 needs --model opus"
    fi
    [ "$(effort_rank "$exec_effort")" -ge "$(effort_rank "$need")" ] \
      || say ERROR header "inline execution needs --effort $need or above (effort $exec_effort)"
  fi
fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh`
Expected: PASS, `0 failed`.

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/plan-amend.test.sh`
Expected: PASS, `0 failed` (`plan-amend` runs `plan-lint`).

Run: `env -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dr-superpowers/scripts/plan-lint docs/superpowers/plans/2026-09-17-dr-superpowers-review-fixes.md --no-probe`
Expected: `0 errors`, and the note `NOTE header: delegated: Task 1 (heavy), Task 6 (heavy)`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): lint total-4 delegation in rule 5"
```

### Task 6: Compute delegation reasons in task-brief

**Files:**
- Modify: `plugins/dr-superpowers/scripts/task-brief:39-65`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh:202-215`

**Interfaces:**
- Consumes: `plan_delegated FILE` (Contracts, Task 4).
- Produces: the Dispatch lines (Contracts).

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, replace:

````text
check "the header lists the delegated tasks" "$(tail -n 1 "$DTMP/h.md")" "**Dispatch:** delegated — Task 2, Task 3"
sed 's/^\*\*Evaluation:\*\* files 1 - spec 1 - coupling 1 - risk 2 = 5$/**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4/; s/risk 3 = 4$/risk 0 = 1/' "$DTMP/plan.md" > "$DTMP/light.md"
brief --header "$DTMP/light.md" "$DTMP/hl.md"
check "a plan with no heavy task has no header Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/hl.md")" "0"
````

with:

````text
check "the header lists the delegated tasks with reasons" "$(tail -n 1 "$DTMP/h.md")" "**Dispatch:** delegated — Task 2 (heavy), Task 3 (heavy)"
sed 's/^\*\*Evaluation:\*\* files 1 - spec 1 - coupling 1 - risk 2 = 5$/**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4/; s/risk 3 = 4$/risk 0 = 1/' "$DTMP/plan.md" > "$DTMP/light.md"
brief --header "$DTMP/light.md" "$DTMP/hl.md"
check "a lone total-4 task in three is delegated" "$(tail -n 1 "$DTMP/hl.md")" "**Dispatch:** delegated — Task 2 (total 4)"
````

Then replace:

````text
check "a Codex-host plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/c2.md")" "0"
rm -rf "$DTMP"
````

with:

````text
check "a Codex-host plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/c2.md")" "0"
four_plan() { # four_plan <file> <total ...> — an inline plan, one task per total (1 or 4)
  local f=$1 i=0 t ev; shift
  printf '# Four\n\n**Execution:** inline — `claude --model sonnet --effort high` — x\n' > "$f"
  for t in "$@"; do
    i=$((i + 1))
    if [ "$t" -eq 4 ]; then ev='files 0 - spec 1 - coupling 1 - risk 2 = 4'; else ev='files 0 - spec 0 - coupling 1 - risk 0 = 1'; fi
    printf '\n### Task %s: t\n\n**Evaluation:** %s\n' "$i" "$ev" >> "$f"
  done
}
four_plan "$DTMP/one4.md" 1 4 1 1 1 1
brief "$DTMP/one4.md" 2 "$DTMP/f2.md"
check "a delegated total-4 task's second line is the Dispatch line" "$(sed -n 2p "$DTMP/f2.md")" "**Dispatch:** delegated — total 4, risk 2"
brief "$DTMP/one4.md" 1 "$DTMP/f1.md"
check "a light task beside a delegated total-4 task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/f1.md")" "0"
brief --header "$DTMP/one4.md" "$DTMP/fh.md"
check "the header names the total-4 reason" "$(tail -n 1 "$DTMP/fh.md")" "**Dispatch:** delegated — Task 2 (total 4)"
four_plan "$DTMP/three4.md" 4 4 4 1 1 1
brief "$DTMP/three4.md" 1 "$DTMP/t1.md"
check "total-4 tasks past a third get no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/t1.md")" "0"
brief --header "$DTMP/three4.md" "$DTMP/th.md"
check "total-4 tasks past a third leave no header Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/th.md")" "0"
rm -rf "$DTMP"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: FAIL on the header-reason checks and the total-4 Dispatch checks.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/task-brief`, replace everything from the line `# Mixed mode: an inline plan delegates its heavy tasks. The line is computed` through the `fi` that closes the per-task `if [ "$dispatch" -eq 1 ]; then` block (the line directly above `  excerpt=$(plan_header "$src" | ...`) with:

```bash
# Mixed mode: an inline plan delegates the tasks plan_delegated names. The
# lines are computed here so an executing session never re-scores a task.
dispatch=0
if ! grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$(plan_header "$src")" \
   && grep -qE '^\*\*Execution:\*\*[ \t]*`?inline' <<<"$(plan_header_line "$src" Execution)"; then
  dispatch=1
fi
delegated=""
[ "$dispatch" -eq 0 ] || delegated=$(plan_delegated "$src")

if [ "$header" -eq 1 ]; then
  plan_header "$src" > "$out"
  if [ -n "$delegated" ]; then
    printf '**Dispatch:** delegated — %s\n' \
      "$(awk -F'\t' '{ printf "%sTask %s (%s)", (NR > 1 ? ", " : ""), $1, $2 }' <<<"$delegated")" >> "$out"
  fi
else
  if ! plan_task_text "$src" "$n" > "$out"; then
    echo "task ${n} not found in ${plan} (no heading matching 'Task ${n}')" >&2
    exit 3
  fi
  # Captured, not piped: grep -q exits at its first match, and under pipefail the
  # writer's SIGPIPE would decide the if.
  if [ -n "$delegated" ] && grep -qxF "$n" <<<"$(cut -f1 <<<"$delegated")"; then
    row=$(plan_scores "$src" | awk -F'\t' -v n="$n" '$1 == n')
    t=$(cut -f2 <<<"$row") r=$(cut -f3 <<<"$row")
    awk -v d="**Dispatch:** delegated — total $t, risk $r" 'NR == 1 { print; print d; next } { print }' "$out" > "$out.tmp"
    mv "$out.tmp" "$out"
  fi
```

The next line after this block stays `  excerpt=$(plan_header "$src" | awk ...`, still inside the `else` branch, followed by its existing `fi`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: PASS, `0 failed`.

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/budget-line.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "feat(superpowers): name delegation reasons in briefs"
```

### Task 7: Document total-4 delegation

**Files:**
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md:118-136`
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md:49`
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md:49-51,160-165,329,337`
- Modify: `plugins/dr-superpowers/reference/delegated-task.md:3-6`
- Modify: `plugins/dr-superpowers/README.md:100-113`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh:91`

**Interfaces:**
- Consumes: the Dispatch lines (Contracts, Task 6).
- Produces: nothing later tasks use.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, find the line `present "a delegating plan gets a preflight" "$INLINE" 'send one `preflight` item'` and insert directly below it:

```bash
present "the preflight keys on a heavy task" "$INLINE" 'naming at least one `(heavy)` task'
absent "the kinds table no longer keys the preflight on any delegation" "$INLINE" 'when the plan delegates any task'
present "the preflight arises only for a heavy task" "$INLINE" '`preflight` arises only for a plan with a heavy task'
present "inline mode names both delegation reasons" "$INLINE" '`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4)`'
present "writing-plans defines four-band tasks" "$P/skills/writing-plans/SKILL.md" 'A task is **four-band**'
present "writing-plans delegates total-4 tasks up to a third" "$P/skills/writing-plans/SKILL.md" 'are a third of the plan or fewer (`3 x four-band <= N`)'
present "using-superpowers names total-4 delegation" "$P/skills/using-superpowers/SKILL.md" 'total-4 tasks while they are a third of the plan or fewer'
present "README names both reasons for delegation" "$P/README.md" 'while they are a third of the plan or fewer, which then get an independent'
present "the delegated loop names both reasons" "$P/reference/delegated-task.md" 'or a total-4 task in a plan where those are a third of the tasks or'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: FAIL on the nine checks above.

- [ ] **Step 3: Rewrite the Execution-line rule in writing-plans**

In `plugins/dr-superpowers/skills/writing-plans/SKILL.md`, replace:

````text
A task is **heavy** when its total is 5 or more or its risk is 3, on any part.
An inline plan delegates its heavy tasks: each runs through
[delegated-task.md](../../reference/delegated-task.md) with an implementer
subagent and the full per-task review.

- `subagent` when more than half the tasks are heavy:
  `claude --model sonnet --effort high`. The controller owns no judgment calls
  — the ruling seat does — so it needs no stronger model.
- Otherwise `inline`, the default. The model follows the highest total among
  the tasks that are not heavy: `sonnet` when every one is 3 or less, `opus`
  when one scores 4 (the Opus-low band). `<e>` is that task's assigned tier's
  effort (`impl-haiku` counts as `low`), raised to `high` when any task is
  heavy: `claude --model <sonnet|opus> --effort <e>`. When every task is heavy
  and your human partner overrides the line to inline, use
  `claude --model opus --effort high` (`plan-lint` checks only the effort).
- Your human partner may override the line; `plan-lint` checks its grammar,
  warns when it disputes the majority rule, and lists the delegated tasks.
````

with:

````text
A task is **heavy** when its total is 5 or more or its risk is 3, on any part.
A task is **four-band** when it is not heavy and its highest total is exactly 4.
An inline plan delegates its heavy tasks, and its four-band tasks while they
are a third of the plan or fewer (`3 x four-band <= N`): each runs through
[delegated-task.md](../../reference/delegated-task.md) with an implementer
subagent and the full per-task review. Past that third, one Opus session costs
less than a seat per task, and no four-band task is delegated. The tasks not
delegated are the **self-implemented** tasks.

- `subagent` when more than half the tasks are heavy:
  `claude --model sonnet --effort high`. The controller owns no judgment calls
  — the ruling seat does — so it needs no stronger model. Four-band tasks never
  count toward this majority.
- Otherwise `inline`, the default. The model is `opus` when a self-implemented
  task totals 4 (so only when four-band tasks exceed a third of the plan), and
  `sonnet` otherwise. `<e>` is the assignment-table effort of the highest
  self-implemented total (`impl-haiku` counts as `low`),
  raised to `high` when any task is delegated:
  `claude --model <sonnet|opus> --effort <e>`. When every task is heavy
  and your human partner overrides the line to inline, use
  `claude --model opus --effort high`.
- Your human partner may override the line; `plan-lint` checks its grammar,
  warns when it disputes the majority rule, and lists the delegated tasks with
  their reasons.
````

- [ ] **Step 4: Name total-4 delegation in using-superpowers**

In `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`, replace:

````text
(at most half the tasks are heavy: total 5 or more, or risk 3; an inline plan delegates those)
````

with:

````text
(at most half the tasks are heavy: total 5 or more, or risk 3; an inline plan delegates those, and total-4 tasks while they are a third of the plan or fewer)
````

- [ ] **Step 5: Key the preflight on a heavy task in executing-plans**

In `plugins/dr-superpowers/skills/executing-plans/SKILL.md`, replace:

````text
**Delegated tasks.** A heavy task is not yours to implement. Its brief's second
line is `**Dispatch:** delegated — total <t>, risk <r>`, and `plan-header.md`
ends with `**Dispatch:** delegated — Task <a>, Task <b>`. Run
````

with:

````text
**Delegated tasks.** A delegated task is not yours to implement: every heavy
task, and each total-4 task while those are a third of the plan or fewer, so it
gets an independent review without putting the whole session on Opus. Its
brief's second line is `**Dispatch:** delegated — total <t>, risk <r>`, and
`plan-header.md` ends with
`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4)`. Run
````

Replace the text below; it ends mid-line at `construction.`, and the rest of that line (` A plan defect that surfaces while you work goes to the seat as a`) and the lines after it stay as they are:

````text
**Preflight.** When `plan-header.md` ends with a `**Dispatch:** delegated`
line, send one `preflight` item to the ruling seat before Task 1 and carry out
its verdicts. A plan with no delegated task has no pre-flight scan: it is one
whole-plan judge dispatch, and a plan of small tasks is low-coupling by
construction.
````

with:

````text
**Preflight.** When `plan-header.md` ends with a `**Dispatch:** delegated`
line naming at least one `(heavy)` task, send one `preflight` item to the
ruling seat before Task 1 and carry out its verdicts. A plan with no heavy task
has no pre-flight scan, even when it delegates total-4 tasks: it is one
whole-plan judge dispatch, and a plan of small tasks is low-coupling by
construction.
````

Replace:

````text
| `preflight` | Once, before Task 1, when the plan delegates any task (Setup) |
````

with:

````text
| `preflight` | Once, before Task 1, when the plan has a heavy task (Setup) |
````

Replace:

````text
executor), and `preflight` arises only for a plan with a delegated task.
````

with:

````text
executor), and `preflight` arises only for a plan with a heavy task.
````

- [ ] **Step 6: Name both reasons in the delegated loop and the README**

In `plugins/dr-superpowers/reference/delegated-task.md`, replace:

````text
dr-superpowers:executing-plans runs it for each task whose brief carries
`**Dispatch:** delegated`.
````

with:

````text
dr-superpowers:executing-plans runs it for each task whose brief carries
`**Dispatch:** delegated`: a heavy task, too large or risky to implement in the
session, or a total-4 task in a plan where those are a third of the tasks or
fewer, delegated so it gets an independent review without putting the whole
session on Opus.
````

In `plugins/dr-superpowers/README.md`, replace:

````text
heavy (total 5 or more, or risk 3). An inline plan delegates its heavy tasks
to an implementer subagent with the full per-task review loop, shared with
subagent mode in `reference/delegated-task.md`, and implements the rest
itself, trading their per-task review for one whole-branch review at the end,
which both modes share. `plan-lint` requires `--model opus` once a task it
````

with:

````text
heavy (total 5 or more, or risk 3). An inline plan delegates its heavy tasks,
which are too large or risky to implement in the session, and its total-4 tasks
while they are a third of the plan or fewer, which then get an independent
review without putting the whole session on Opus. Each delegated task runs
through an implementer subagent with the full per-task review loop, shared with
subagent mode in `reference/delegated-task.md`; the session implements the rest
itself, trading their per-task review for one whole-branch review at the end,
which both modes share. `plan-lint` requires `--model opus` once a task it
````

- [ ] **Step 7: Run the tests to verify they pass**

Run, one at a time with `env -u CLAUDE_CONFIG_DIR timeout 300 bash`: `plugins/dr-superpowers/tests/inline-mode.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`, `plugins/dr-superpowers/tests/hook.test.sh`.
Expected: each ends `0 failed` (`review-route` pins `an inline plan delegates those`, `raised to \`high\` when any task is` and `` `--effort high` once it delegates``; `hook` checks the 4800-byte cap).

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/skills/writing-plans/SKILL.md \
  plugins/dr-superpowers/skills/using-superpowers/SKILL.md \
  plugins/dr-superpowers/skills/executing-plans/SKILL.md \
  plugins/dr-superpowers/reference/delegated-task.md plugins/dr-superpowers/README.md \
  plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "docs(superpowers): document total-4 delegation"
```

### Task 8: Route the final Claude review

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route:13-20,33,35,111`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh:395`

**Interfaces:**
- Consumes: `plan_shape` (existing, `scripts/review-route:55-66`).
- Produces: `review-route PLAN_FILE --final` (Contracts).

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert directly above the line `# --- README, version and program amendment -------------------------------------`:

```bash
# --- the final whole-branch review ---
shape_plan "$TMP/final-plain.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1' \
  '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5'
rule "$TMP/final-plain.md" --final
check "final: a plain plan takes judge-opus" "$out" "review-seat final primary=dr-superpowers:judge-opus fallback=- reason=plain"
shape_plan "$TMP/final-risk.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1' \
  '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4'
rule "$TMP/final-risk.md" --final
check "final: risk 3 is intricate" "$out" \
  "review-seat final primary=dr-superpowers:judge-fable fallback=dr-superpowers:judge-opus reason=intricate"
shape_plan "$TMP/final-six.md" '**Evaluation:** files 1 - spec 1 - coupling 2 - risk 2 = 6'
rule "$TMP/final-six.md" --final
check "final: total 6 is intricate" "$out" \
  "review-seat final primary=dr-superpowers:judge-fable fallback=dr-superpowers:judge-opus reason=intricate"
review_surface false
rule "$TMP/final-plain.md" --final
check "final: the seat does not read the Codex gate" "$out" "review-seat final primary=dr-superpowers:judge-opus fallback=- reason=plain"
rule "$TMP/final-plain.md" --final extra
check "final: an extra argument exits 2" "$rc" "2"
rule "$TMP/final-plain.md" --task
check "final: --task with no id still exits 2" "$rc" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on the four `final:` seat checks (exit 2 with the usage message).

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/review-route`, replace:

````text
#        review-route PLAN_FILE --ruling KIND [ID ...]
````

with:

````text
#        review-route PLAN_FILE --ruling KIND [ID ...]
#        review-route PLAN_FILE --final
````

Replace:

````text
usage() { die "usage: review-route PLAN_FILE --task ID [ID ...] | --plan-round R | --ruling KIND [ID ...]"; }

[ $# -ge 3 ] || usage
````

with:

````text
usage() { die "usage: review-route PLAN_FILE --task ID [ID ...] | --plan-round R | --ruling KIND [ID ...] | --final"; }

[ $# -ge 2 ] || usage
````

Replace:

````text
  --task) shift ;;
````

with:

````text
  --final)
    [ $# -eq 1 ] || usage
    plan_shape
    if [ "$intricate" -eq 1 ]; then
      printf 'review-seat final primary=%s fallback=%s reason=intricate\n' "$FABLE" "$OPUS"
    else
      printf 'review-seat final primary=%s fallback=- reason=plain\n' "$OPUS"
    fi
    exit 0 ;;
  --task) shift; [ $# -ge 1 ] || usage ;;
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): route the final Claude review"
```

### Task 9: Route the final fix wave

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: `plan_ledger`, `plan_task_text`, `plan_tasks`, `plan_header_line`, `_PLAN_AWK` (existing, `scripts/lib/plan.sh`); the `--final` case and relaxed argument check (Task 8).
- Produces: `review-route PLAN_FILE --final-fix FILE [FILE ...]` (Contracts).

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert directly above the line `# --- README, version and program amendment -------------------------------------` (below the Task 8 block):

```bash
# --- the final fix wave's implementer ---
FF="$TMP/ff"
git init -q "$FF"
mkdir -p "$FF/docs" "$FF/.superpowers/sdd/plan"
sed 's/^|//' > "$FF/docs/plan.md" <<'EOF'
|# Fix Wave Fixture
|
|**Execution:** inline — `claude --model opus --effort low` — x
|
|### Task 1: below the floor
|
|**Files:**
|- Create: `a.txt`
|- Test: `tests/a.test.sh`
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1
|
|### Task 2: line range
|
|**Files:**
|- Modify: `b.txt:10-20`
|
|**Implementer:** dr-superpowers:impl-opus-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 3: escalated
|
|**Files:**
|- Modify: `c.txt`
|
|**Implementer:** dr-superpowers:impl-sonnet-medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 4: reserve
|
|**Files:**
|- Modify: `d.txt`
|
|**Implementer:** dr-superpowers:impl-fable-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|**Override:** owner assigned Fable
|
|### Task 5: inline
|
|**Files:**
|- Modify: `e.txt`
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 6: split
|
|#### Part A: small half
|
|**Files:**
|- Modify: `f.txt`
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: larger half
|
|**Files:**
|- Modify: `g.txt`
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
|
|### Task 7: line list
|
|**Files:**
|- Modify: `h.txt:3-4,9`
|
|**Implementer:** dr-superpowers:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3
EOF
sed 's/^|//' > "$FF/.superpowers/sdd/plan/progress.md" <<'EOF'
|# SDD ledger — plan: docs/plan.md
|Task 1: implementer impl-sonnet-low (assigned; base aaaaaaa)
|Task 3: implementer dr-superpowers:impl-sonnet-medium (assigned; base bbbbbbb)
|Task 3: fix round 4/5 (1 addressed, 1 open — x; commits bbbbbbb..ccccccc; escalated impl-sonnet-medium -> impl-opus-medium)
|Task 5: implementer inline (assigned; base ddddddd)
|Task 5: escalated inline -> subagent — three fix rounds
EOF
fix() { out=$(bash "$ROUTE" "$FF/docs/plan.md" --final-fix "$@" 2>"$TMP/err"); rc=$?; }
FIXSEAT="review-seat final-fix primary=dr-superpowers"
fix zzz.txt
check "final-fix: no matched task is the floor" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=floor"
fix a.txt
check "final-fix: a low tier is raised to the floor" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:1"
fix tests/a.test.sh
check "final-fix: a Test entry matches" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:1"
fix b.txt
check "final-fix: a :line-range suffix in the plan is ignored" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:2"
fix b.txt:12
check "final-fix: a finding's own line suffix is ignored" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:2"
fix h.txt
check "final-fix: a :line-list suffix in the plan is ignored" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:7"
fix h.txt:3,9
check "final-fix: a finding's own line list is ignored" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:7"
fix a.txt b.txt
check "final-fix: the highest of two matched tasks" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:1,2"
fix c.txt
check "final-fix: the ledger's escalated agent counts" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:3"
fix d.txt
check "final-fix: a reserve tier is capped at impl-opus-high" "$out" "$FIXSEAT:impl-opus-high fallback=- reason=tasks:4"
fix e.txt
check "final-fix: an inline implementer is the Execution line's rung" "$out" "$FIXSEAT:impl-opus-low fallback=- reason=tasks:5"
fix g.txt
check "final-fix: a split task's parts count as the task" "$out" "$FIXSEAT:impl-opus-low fallback=- reason=tasks:6"
fix zzz.txt c.txt
check "final-fix: an unmatched file beside a matched one" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:3"
sed 's/^|//' > "$FF/.superpowers/sdd/plan/amendments.md" <<'EOF'
|## A1 — Task 1
|
|### Old
|
|````
|- Create: `a.txt`
|````
|
|### New
|
|````
|- Create: `a2.txt`
|````
EOF
fix a2.txt
check "final-fix: an amended Files block is read" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:1"
fix a.txt
check "final-fix: a file amended away no longer matches" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=floor"
rm -f "$FF/.superpowers/sdd/plan/amendments.md"
fix
check "final-fix: no file exits 2" "$rc" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on every `final-fix:` seat check (exit 2 with the usage message).

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/review-route`, replace:

````text
#        review-route PLAN_FILE --final
````

with:

````text
#        review-route PLAN_FILE --final
#        review-route PLAN_FILE --final-fix FILE [FILE ...]
````

Replace:

````text
| --final"; }
````

with:

````text
| --final | --final-fix FILE [FILE ...]"; }
````

Directly above the line `case "$1" in`, insert:

```bash
# agent_rank AGENT — reference/ladder.md §Why this terminates: model_rank * 10 +
# effort_rank. Nothing for a name that is not an implementer.
agent_rank() {
  local m e
  if [ "$1" = impl-haiku ]; then echo 0; return; fi
  [[ "$1" =~ ^impl-(sonnet|opus|fable)-(low|medium|high|xhigh|max)$ ]] || return 0
  case ${BASH_REMATCH[1]} in sonnet) m=1 ;; opus) m=2 ;; *) m=3 ;; esac
  case ${BASH_REMATCH[2]} in low) e=0 ;; medium) e=1 ;; high) e=2 ;; xhigh) e=3 ;; *) e=4 ;; esac
  echo $((m * 10 + e))
}

# task_files N — the paths every **Files:** block of task N names, backticks and
# a :line-range or :line-list suffix (b.txt:10-20, plan-lint:143,239) removed.
task_files() {
  plan_task_text "$src" "$1" | awk "$_PLAN_AWK"'
    in_fence($0) { on = 0; next }
    /^\*\*Files:\*\*/ { on = 1; next }
    on && /^- (Create|Modify|Test):/ {
      p = $0; sub(/^- (Create|Modify|Test):[ \t]*/, "", p); gsub(/`/, "", p)
      sub(/[ \t].*$/, "", p); sub(/:[0-9][0-9,-]*$/, "", p)
      print p; next
    }
    { on = 0 }
  '
}

# task_agents N — the implementer task N last ran on: the ledger's last assigned
# agent, escalation target or HANDBACK target, or else every **Implementer:**
# line of the task (one per part). Plugin prefixes are dropped. The inline
# marker "escalated inline -> subagent" names no agent, so only impl- targets
# count.
task_agents() {
  local agent=""
  [ -z "$ledger" ] || agent=$(tr -d '\r' < "$ledger" | awk -v p="Task $1: " '
    index($0, p) != 1 { next }
    match($0, /: implementer [^ ]+ \(assigned/) {
      s = substr($0, RSTART, RLENGTH); sub(/^: implementer /, "", s); sub(/ \(assigned$/, "", s); a = s
    }
    match($0, /(escalated [^ ]+ -> |HANDBACK to )[^ ;)]+/) {
      s = substr($0, RSTART, RLENGTH); sub(/^.* /, "", s); sub(/^.*:/, "", s)
      if (s ~ /^impl-/) a = s
    }
    END { sub(/^.*:/, "", a); if (a != "") print a }
  ')
  if [ -n "$agent" ]; then printf '%s\n' "$agent"; return; fi
  plan_task_text "$src" "$1" | sed -nE 's/^\*\*Implementer:\*\*[ \t]*`?([^` \t]+)`?.*/\1/p' | sed 's/^.*://'
}

# final_fix FILE... — the fix wave takes the highest tier among the tasks whose
# Files blocks name the findings' paths, between impl-sonnet-high and
# impl-opus-high: the wave has no second wave and no escalation, so its tier
# follows the work it touches.
final_fix() {
  local execution m e rung="" n _title agents agent rank best=-1 tasks="" files file hit
  local models=(haiku sonnet opus fable) efforts=(low medium high xhigh max)
  ledger=$(plan_ledger "$plan")
  execution=$(plan_header_line "$src" Execution)
  if [[ "$execution" =~ claude\ --model\ ([a-z0-9.-]+)\ --effort\ ([a-z]+) ]]; then
    m=${BASH_REMATCH[1]} e=${BASH_REMATCH[2]}
    case $m in
      *haiku*) rung=impl-haiku ;;
      *sonnet*) rung=impl-sonnet-$e ;;
      *opus*) rung=impl-opus-$e ;;
      *fable*) rung=impl-fable-$e ;;
    esac
  fi
  while IFS=$'\t' read -r n _title; do
    [ -n "$n" ] || continue
    files=$(task_files "$n")
    hit=0
    for file in "$@"; do
      file=${file#./}
      [[ "$file" =~ ^(.+):[0-9][0-9,-]*$ ]] && file=${BASH_REMATCH[1]}
      if grep -qxF -- "$file" <<<"$files"; then hit=1; break; fi
    done
    [ "$hit" -eq 1 ] || continue
    tasks="${tasks:+$tasks,}$n"
    agents=$(task_agents "$n")
    while IFS= read -r agent; do
      [ "$agent" != inline ] || agent=$rung
      rank=$(agent_rank "$agent")
      [ -z "$rank" ] || [ "$rank" -le "$best" ] || best=$rank
    done <<<"$agents"
  done < <(plan_tasks "$src")
  if [ -z "$tasks" ]; then
    printf 'review-seat final-fix primary=dr-superpowers:impl-sonnet-high fallback=- reason=floor\n'
    return
  fi
  [ "$best" -ge 12 ] || best=12
  [ "$best" -le 22 ] || best=22
  printf 'review-seat final-fix primary=dr-superpowers:impl-%s-%s fallback=- reason=tasks:%s\n' \
    "${models[best / 10]}" "${efforts[best % 10]}" "$tasks"
}

````

Then, in the `case "$1" in` block, replace:

````text
  --task) shift; [ $# -ge 1 ] || usage ;;
````

with:

````text
  --final-fix)
    shift
    [ $# -ge 1 ] || usage
    final_fix "$@"
    exit 0 ;;
  --task) shift; [ $# -ge 1 ] || usage ;;
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: PASS, `0 failed`.

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/ladder.test.sh`
Expected: PASS, `0 failed` (unchanged).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): route the final fix wave"
```

### Task 10: Name the final-review seats in the skills

**Files:**
- Modify: `plugins/dr-superpowers/reference/final-review.md:32-36,70-73`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md:243,251-253,273-274,312-314,539`
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md:419-421`
- Modify: `plugins/dr-superpowers/agents/judge-fable.md:3`
- Modify: `plugins/dr-superpowers/agents/judge-opus.md:3`
- Modify: `plugins/dr-superpowers/README.md:181`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh:123`

**Interfaces:**
- Consumes: `review-route PLAN_FILE --final` (Task 8) and `review-route PLAN_FILE --final-fix FILE [FILE ...]` (Task 9), per Contracts.
- Produces: the ledger line `Final fix: implementer <agent> (assigned; base <sha7>)` (Contracts).

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, find the line `present "the shared reference names both modes" "$FINAL" "Inline mode"` and insert directly below it:

```bash
present "final review routes the Claude seat" "$FINAL" '`scripts/review-route PLAN_FILE --final` and dispatch'
absent "final review drops the most capable model" "$FINAL" 'most capable'
present "final review routes the fix subagent" "$FINAL" '`scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]`'
present "final review ledgers the fix subagent" "$FINAL" '`Final fix: implementer <agent> (assigned; base <sha7>)`'
absent "subagent mode drops the most capable final seat" "$SDD" 'most capable available'
absent "subagent mode drops the most capable final reviewer" "$SDD" 'final reviewer on the most capable model'
present "subagent ledger has the Final fix line" "$SDD" 'Final fix: implementer <agent> (assigned; base <sha7>)'
present "subagent mode recovers a lost fix wave" "$SDD" 'A `Final fix:` line and no `Final review:` line'
present "inline mode names the final seat" "$INLINE" '`scripts/review-route PLAN_FILE --final` prints'
present "judge-fable takes an intricate final review" "$P/agents/judge-fable.md" 'the final whole-branch review of an intricate plan'
present "judge-opus takes a plain final review" "$P/agents/judge-opus.md" 'the final whole-branch review of a plain plan'
present "README names the final seats" "$P/README.md" 'The final whole-branch review runs on `judge-fable` for an intricate plan'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: FAIL on the twelve checks above.

- [ ] **Step 3: Name the seats in final-review.md**

In `plugins/dr-superpowers/reference/final-review.md`, replace:

````text
1. **Claude review.** Dispatch a general-purpose agent on the most capable
   available model, using dr-superpowers:requesting-code-review's
   [code-reviewer.md](../skills/requesting-code-review/references/code-reviewer.md)
   with `[DIFF_FILE]` set to the package path, `[PLAN_OR_REQUIREMENTS]` to the
   spec and plan paths, and the SHAs to `MERGE_BASE` and `HEAD`.
````

with:

````text
1. **Claude review.** Run `scripts/review-route PLAN_FILE --final` and dispatch
   the `primary` it prints: `dr-superpowers:judge-fable` for an intricate plan
   (a task at risk 3 or totalling 6), `dr-superpowers:judge-opus` otherwise.
   When Fable is unavailable or your human partner declined it, dispatch the
   `fallback` instead and say so aloud. Use dr-superpowers:requesting-code-review's
   [code-reviewer.md](../skills/requesting-code-review/references/code-reviewer.md)
   with `[DIFF_FILE]` set to the package path, `[PLAN_OR_REQUIREMENTS]` to the
   spec and plan paths, and the SHAs to `MERGE_BASE` and `HEAD`. The judge
   agents are read-only; the package file means the template's git fallback
   never applies. A Codex-host plan takes its final-review seat from
   [native-codex.md](native-codex.md) instead.
````

Replace:

````text
a real session's final-review fix wave cost more than all its tasks combined.
````

with:

````text
a real session's final-review fix wave cost more than all its tasks combined.

**The fix subagent** (subagent mode). Run
`scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]` with every
repository-relative path the findings name. It prints the highest implementer
tier among the tasks whose `**Files:**` blocks name those paths, as the ledger
last recorded each (an escalation counts, and an `inline` implementer counts as
the Execution line's rung), raised to `impl-sonnet-high` and capped at
`impl-opus-high`; no matched task gives `reason=floor`. Append
`Final fix: implementer <agent> (assigned; base <sha7>)` to the ledger, then
dispatch the printed `primary` as `subagent_type`, with no `model` argument.
````

- [ ] **Step 4: Update subagent-driven-development**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace:

````text
| Final review | general-purpose | Explicit, most capable available |
````

with:

````text
| Final review | The seat `scripts/review-route PLAN_FILE --final` prints ([final-review.md](../../reference/final-review.md) step 1); its `fallback` when Fable is unavailable or your human partner declined it, said aloud | None |
| Final fix wave | The implementer `scripts/review-route PLAN_FILE --final-fix <file> ...` prints ([final-review.md](../../reference/final-review.md) §Fixing what it finds) | None |
````

Replace:

````text
cheap-to-mid tier; a subtle concurrency fix takes more. The final whole-branch
review takes the most capable available model.
````

with:

````text
cheap-to-mid tier; a subtle concurrency fix takes more.
````

In the ledger grammar block, replace:

````text
Ruling: <what> — <why> — <cost if wrong>
Final review: clean (commits <merge-base7>..<head7>[, K parked])
````

with:

````text
Ruling: <what> — <why> — <cost if wrong>
Final fix: implementer <agent> (assigned; base <sha7>)
Final review: clean (commits <merge-base7>..<head7>[, K parked])
````

Replace:

````text
**Plan state.** Every task complete and no `Final review:` line: go to Final
Review. A `Final review: clean` line: the review is done — go to
````

with:

````text
**Plan state.** Every task complete and no `Final review:` line: go to Final
Review. A `Final fix:` line and no `Final review:` line: the fix wave was
dispatched; after compaction the agent id is gone, so re-dispatch that agent
fresh, then continue Final Review at the scoped re-review. A
`Final review: clean` line: the review is done — go to
````

Replace:

````text
[final-review.md: package the branch; general-purpose final reviewer on the most capable model; Codex round in the background]
````

with:

````text
[final-review.md: package the branch; review-route --final prints judge-opus for this plain plan; Codex round in the background]
````

- [ ] **Step 5: Update executing-plans, the judge agents and the README**

In `plugins/dr-superpowers/skills/executing-plans/SKILL.md`, replace:

````text
[final-review.md](../../reference/final-review.md), the procedure both
execution skills share. In this mode it runs in this session, unless the last
````

with:

````text
[final-review.md](../../reference/final-review.md), the procedure both
execution skills share; its reviewer is the seat
`scripts/review-route PLAN_FILE --final` prints, and its fix wave is your own
pass. In this mode it runs in this session, unless the last
````

In `plugins/dr-superpowers/agents/judge-fable.md`, replace:

````text
the final review's two-list dedupe, plan-review round 1
````

with:

````text
the final review's two-list dedupe, the final whole-branch review of an intricate plan, plan-review round 1
````

In `plugins/dr-superpowers/agents/judge-opus.md`, replace:

````text
for routine rulings, approach ranking and distillation checks,
````

with:

````text
for routine rulings, the final whole-branch review of a plain plan, approach ranking and distillation checks,
````

In `plugins/dr-superpowers/README.md`, replace:

````text
capped by the plan's highest task total. The final whole-branch review gains a Codex round. When both
````

with:

````text
capped by the plan's highest task total. The final whole-branch review runs on `judge-fable` for an intricate plan and `judge-opus` otherwise, its one fix subagent on the highest tier among the tasks the findings touch, and gains a Codex round. When both
````

- [ ] **Step 6: Run the tests to verify they pass**

Run, one at a time with `env -u CLAUDE_CONFIG_DIR timeout 300 bash`: `plugins/dr-superpowers/tests/inline-mode.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`, `plugins/dr-superpowers/tests/fleet.test.sh`.
Expected: each ends `0 failed`.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/reference/final-review.md \
  plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md \
  plugins/dr-superpowers/skills/executing-plans/SKILL.md plugins/dr-superpowers/agents/judge-fable.md \
  plugins/dr-superpowers/agents/judge-opus.md plugins/dr-superpowers/README.md \
  plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "docs(superpowers): name the final-review seats"
```

### Task 11: Escalate out of inline mode above both rungs

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md:304`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/escalation.md:28-30`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh:103`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing later tasks use.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, find the line `present "subagent mode reads the escalation line" "$SDD" "escalated inline -> subagent"` and insert directly below it:

```bash
ESC="$P/skills/subagent-driven-development/references/escalation.md"
present "the inline recovery row ranks above both" "$SDD" "ranked strictly above both the task's \`**Implementer:**\` agent and the inline session's rung"
present "escalation names the inline exit" "$ESC" '## Escalating out of inline mode'
present "escalation walks from the higher rung" "$ESC" 'dispatch its successor on the'
present "escalation gives the worked example" "$ESC" '`impl-opus-high`, not `impl-opus-low`'
present "escalation names the session rung" "$ESC" '`impl-<model>-<effort>` (`haiku` as `impl-haiku`)'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: FAIL on the five checks above.

- [ ] **Step 3: Rewrite the recovery row**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace the start of the table row below; the rest of that line, from ` with the brief and the task's preceding fix-round lines;` to its closing `|`, stays as it is:

````text
| `escalated inline -> subagent` | Inline mode escalated this task here. Dispatch the successor rung of the task's `**Implementer:**` agent ([escalation.md](references/escalation.md)) fresh at round 1 of 5,
````

with:

````text
| `escalated inline -> subagent` | Inline mode escalated this task here. Dispatch the first rung on the escalation table ranked strictly above both the task's `**Implementer:**` agent and the inline session's rung, the successor of whichever ranks higher ([escalation.md](references/escalation.md) §Escalating out of inline mode) fresh at round 1 of 5,
````

- [ ] **Step 4: Add the section to escalation.md**

In `plugins/dr-superpowers/skills/subagent-driven-development/references/escalation.md`, replace:

````text
[external-executor.md](../../../reference/external-executor.md).

## Recording an escalation
````

with:

````text
[external-executor.md](../../../reference/external-executor.md).

## Escalating out of inline mode

A task whose last ledger line is `escalated inline -> subagent` failed in an
inline session that may already run above the task's assigned tier, so the
successor of the `**Implementer:**` agent alone can land at or below the tier
that just failed. Rank both with [ladder.md](../../../reference/ladder.md)
§Why this terminates:

- the task's `**Implementer:**` agent, and
- the inline session's rung: the Execution line's `--model` and `--effort` as
  `impl-<model>-<effort>` (`haiku` as `impl-haiku`).

Start the walk from whichever ranks higher and dispatch its successor on the
escalation table, the first rung ranked strictly above both. For example,
`impl-sonnet-low` assigned in an `impl-sonnet-high` session dispatches
`impl-opus-high`, not `impl-opus-low`. When that start is `impl-opus-high`, its
successor is `SPLIT`, handled as §The top rung is SPLIT describes.

## Recording an escalation
````

- [ ] **Step 5: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: exit 0 (the new `ladder.md` link resolves).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md \
  plugins/dr-superpowers/skills/subagent-driven-development/references/escalation.md \
  plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "fix(superpowers): escalate out of inline above both"
```

### Task 12: Release 1.12.0

**Files:**
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json:5`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json:3`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh:402-403`

**Interfaces:**
- Consumes: every earlier task's commits (verification runs over them).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace:

````text
present "the Claude manifest is 1.11.1" "$P/.claude-plugin/plugin.json" '"version": "1.11.1"'
present "the Codex manifest is 1.11.1" "$P/.codex-plugin/plugin.json" '"version": "1.11.1"'
````

with:

````text
present "the Claude manifest is 1.12.0" "$P/.claude-plugin/plugin.json" '"version": "1.12.0"'
present "the Codex manifest is 1.12.0" "$P/.codex-plugin/plugin.json" '"version": "1.12.0"'
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on the two manifest checks.

- [ ] **Step 3: Bump both manifests**

In `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`, replace `"version": "1.11.1"` with `"version": "1.12.0"`.

- [ ] **Step 4: Run the full verification**

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: exit 0.

Run:

```bash
for t in plugins/dr-superpowers/tests/*.test.sh; do
  env -u CLAUDE_CONFIG_DIR timeout 300 bash "$t" > /dev/null 2>&1 || echo "FAILED: $t"
done; echo "suites done"
```

Expected: only `suites done`.

Run alone: `env -u CLAUDE_CONFIG_DIR timeout 900 node scripts/test-all.mjs`
Expected: every suite passes except `tests/ui-discovery.test.mjs` ("documented Win32 discovery finds centrally managed versions", `bash: rg: command not found`).

Run each: `timeout 120 claude plugin validate .`, then `timeout 120 claude plugin validate plugins/<name>` for `dr-status`, `dr-superpowers`, `dcc-darkraise-ui`, `dcc-darkraise-win32ui`.
Expected: each passes.

Every command above runs in the foreground under `timeout`, so nothing started here outlives its step; do not start any of them in the background.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json \
  plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): release 1.12.0"
```
