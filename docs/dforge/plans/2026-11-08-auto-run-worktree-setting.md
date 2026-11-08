# Auto Runs Follow the Worktree Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An auto run follows the `worktree` setting (`ask`, `always`, `never`): `always` creates the execution worktree unasked, `never` works in the primary checkout on a branch of its own with the user's uncommitted changes carried and never committed, and `ask` asks at the spec review or the auto-run offer.

**Architecture:** The run state gains `isolation`, `branch`, `branchBase` and `carried`, written by `auto-run start --isolation` and a new `auto-run setup-branch`. One guard (`ar_guard`) replaces the primary-checkout test: it refuses the run's base branch, a HEAD off the recorded in-place branch, and (for worktree runs only) the primary checkout; a carried-path check refuses any commit that includes a carried path at `task-complete`, `phase final` and `phase finish`. The skills then read the run state at setup, resume, recovery, QA cleanup, the executor lanes and finishing, and the spec review and offer collect the `ask` answer.

**Tech Stack:** Bash scripts and suites, jq, Node (`config/schema.mjs`, `scripts/test-all.mjs`, `scripts/test-shards.mjs`), Markdown skills.

**Spec:** `docs/dforge/specs/2026-11-08-auto-run-worktree-setting-design.md`

**Execution:** inline — `claude --model opus --effort high` — the owner's inline-only change (PR #43) has the session implement every task; the hardest is total 8

**Parallelism:** sequential — inline execution

**Task check:** `timeout 1500 node scripts/test-all.mjs` — the full suite last passed in 173 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs`

**CI:** `.github/workflows/validate.yml .github/workflows/release.yml` — platforms: GNU Linux (self-hosted), uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/validate-repository.mjs`; `node scripts/test-all.mjs`; `claude plugin validate .`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: Windows Git Bash, uutils (ubuntu-latest)

**Plan review:** 2026-11-08 — dforge:judge-opus — executability 11 / coherence 13 / coverage 15 / assumptions 12 (round 1)

## Global Constraints

- English only; commits `<type>(<scope>): <subject>`, subject ≤ 50 chars, no AI attribution, author `Darkraise <quangtc94@gmail.com>`.
- Do not edit historical plans, specs, notes or registers other than this plan's own register.
- Preserve existing `DCC_*` variables and statusline user storage paths.
- Bound every test and CLI run with a timeout; call the Claude CLI as `/root/.local/bin/claude`; unset `CLAUDE_CONFIG_DIR` in suites that read budgets.
- Every new shell suite gets a weight in `scripts/test-shards.mjs` at most 80% of its limit (`tests/test-shards.test.mjs` enforces it).
- A state file written before this change (no `isolation`, `branch`, `branchBase` or `carried` field) behaves exactly as today: missing `isolation` reads as `worktree`.
- The attended path of using-git-worktrees, the `worktree` setting's values and default, the scratch worktrees (`scripts/task-step`, the final review's integration run, acceptance QA's mutation check) and parallel waves are unchanged.
- Update an existing test's expectation only where this plan's rules change that outcome, never to make an unrelated failure pass; name each changed pin in the commit body.
- Every phrase an acceptance check pins stays on one source line: the checks match line by line (`grep -F`), so never wrap a pinned phrase across lines in a hard-wrapped Markdown file.
- Windows Git Bash: a native program given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open — convert with `cygpath -m` (`dr_native_path`, `scripts/lib/native-path.sh`) and feed `jq` a file on stdin.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool — normalise both with `cygpath -m` or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r` — pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes — pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` fails — import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing does not exclude a second process — use `set -C` or `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started — run it under `setsid` and signal the group.

## Contracts

- **C1 run state fields** (`.dforge/sdd/auto-run.json`, written through `ar_update`): `isolation` — `"worktree"` or `"in-place"`, set by `start`; `branch`, `branchBase` (a full commit sha), `carried` (an array of repository-relative paths) — `null` until `setup-branch` records them. A missing or null `isolation` reads as `worktree` everywhere.
- **C2 `scripts/auto-run start --spec P [--register R] [--isolation worktree|in-place] [--force]`:** without `--isolation` it records `worktree`. Any other value prints `auto-run: --isolation must be worktree or in-place` and exits 2 before any state is written. The usage text names the flag.
- **C3 `scripts/auto-run setup-branch NAME`** (bound run): exits 4, recording nothing, with one stderr line each: `auto-run: <NAME> is the run's base branch` when NAME equals `base`; `auto-run: HEAD is not on <NAME>` when `git symbolic-ref --short -q HEAD` is not NAME; `auto-run: staged changes in the primary checkout: <paths>` (space-separated) when any `git status --porcelain=v1 -z --untracked-files=all` entry has an index column other than space or `?`. Otherwise records `branch`=NAME, `branchBase`=`git rev-parse HEAD`, `carried`=every path that status lists (an untracked directory as each file; a rename entry as both paths), and exits 0. `scripts/auto-run carried` prints the carried paths, one per line, and nothing when none are recorded.
- **C4 status line:** `ar_status` appends ` — isolation <worktree|in-place>` after ` — register <r>`, then ` — branch <name>` once a branch is recorded, both before ` — setup due`.
- **C5 the guard** (`ar_guard` in `scripts/lib/auto-run.sh`) refuses when: (1) HEAD's branch is the state's `base`, or HEAD is detached (in any checkout) while `base` is null; (2) `isolation` is `in-place`, `branch` is recorded and HEAD is not on it; (3) `isolation` is `worktree` and the session is in the primary checkout. Precedence: a `worktree` run checks (3) first, then (1); an `in-place` run checks (1), then (2). The first rule that holds picks the message and the stop reason, so a worktree run on its base in the primary checkout keeps today's message and today's stop reason. `phase execute` on (3) keeps today's message `auto-run: this is the primary checkout; create the execution worktree first (dforge:using-git-worktrees), then run auto-run phase execute from it`; on (1) or (2) it prints `auto-run: HEAD is not on the run's branch; follow dforge:using-git-worktrees Step 0 for the run, then run auto-run phase execute again`. Both exit 4 with the phase unchanged.
- **C6 the carried check** (`ar_carried_hit`): the first path of `git diff --name-only <branchBase>..HEAD` that is in `carried`; empty when `branchBase` is null. `task-complete` in the execute or final phase stops the run (exit 5) on the guard — reason `a task was completed on the run's base branch` for (1), `a task was completed off the run's branch` for (2), today's `a task was completed in the primary checkout` for (3) — or on a carried hit, reason `carried path <p> was committed`; its stderr line stays `auto-run: <reason>; the run has stopped. End as reference/auto-run.md §Stopping says.` `phase final` and `phase finish` on a carried hit print `auto-run: carried path <p> was committed; stop the run` and exit 4 with the phase unchanged.
- **C7 branch name:** `auto/<plan slug>`, the slug being the plan filename without `.md` and its `YYYY-MM-DD-` prefix (as `ar_start` strips the spec's), suffixed `-2`, `-3`, … until `git show-ref --verify --quiet refs/heads/<name>` fails.
- **C8 acceptance suite:** `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`, created by Task 1 with helpers `check NAME GOT WANT`, `present NAME FILE NEEDLE`, `absent NAME FILE NEEDLE`, `has NAME HAYSTACK NEEDLE`, `beat SESSION`, `arun DIR SESSION ARGS…` (auto-run from DIR under `--session SESSION` with a live cockpit), `field NAME` (a state field as a string, `null` when unset), `fresh` (a new repository at `$REPO` on `main` with tracked `a.txt` and `b.txt`, no run, no `$TMP/side`), `inplace SESSION` (`fresh`, start an `in-place` run, `git switch -c auto/widget`, `setup-branch auto/widget`); variables `P` (plugin root), `S` (`$P/scripts`), `AR`, `TMP`, `REPO`, `STATE`, `SPEC`. Each later task appends one block headed `# --- Task <N> ---` above the `# --- summary ---` block, which stays last.
- **C9 Decisions line:** the spec review records the worktree answer as its own paragraph in `## Decisions`, exactly `Worktree: worktree` or `Worktree: in-place`.
- **C10 executor fallback ledger line:** `Task <N>: implementer inline (assigned; base <sha7>; executor <id> unavailable - no linked worktree)`.

## Assumptions (evidence)

- The installed dforge (4.12.0) still delegates heavy tasks and would WARN that most tasks are heavy; the repository's dforge (4.13.0, PR #43, merged 2026-11-08 as 25a97605) makes the session implement every task. The executing session follows the merged behaviour: it implements every task itself and logs `Ruling: heavy task self-implemented — owner's inline-only change — none` once.
- `.dforge/` is git-ignored (`git check-ignore -v .dforge/sdd/auto-run.json` → `.gitignore:15`, 2026-11-08), and `ar_start` self-ignores the state directory (`dforge_self_ignore`, `scripts/lib/auto-run.sh:206`), so a fixture's `git status` never lists the state file; a fixture passes `--register docs/r.md` so `start` creates no register file to dirty the tree.
- Existing pins this plan changes, all in `plugins/dforge/tests/auto-run.test.sh`: line 88 (the whole status line gains ` — isolation worktree`, Task 1); lines 168-170 (a run started in a linked worktree on its own base is refused until Setup switches branches, Task 2, spec A4 and A12); lines 633 and 729 (`worktree first` becomes `workspace first`, Task 2). Lines 181-182 and 645-646 (a worktree run on `main` in the primary checkout) keep today's message and stop reason through C5's precedence. `plugins/dforge/tests/auto-run-skills.test.sh` lines 30, 109, 122 and 123 change in Task 3.
- Shard weight: `tests/auto-run.test.sh` ran in 36 s on this Linux host on 2026-11-08 (`time bash tests/auto-run.test.sh`) and is weighted 507 s on Windows, a ratio of about 14; the new suite makes roughly a quarter of its auto-run and git calls, so about 10 s on Linux and a 150 s weight.
- `ar_get` prints nothing for a null or missing field (`scripts/lib/auto-run.sh:103-105`), which C1's `worktree` default relies on.
- `plugins/dforge/tests/inline-only.acceptance.test.sh:244` pins the version to `4.13.0`; Task 6's bump replaces it with an at-least check.
- Plan review round 1 scored executability 11, coherence 13 and assumptions 12 (borderline): its 6 Important findings (unlisted pins at `auto-run.test.sh:88`, `:633`, `:729`; C5's rule precedence; C5's detached-HEAD narrowing; the locale-dependent sort; subagent-driven-development's `phase final` exit) and 7 Minor ones were fixed in the plan; no round returned a Critical or a score of 8 or below, so no second round runs.
- The full suite passes in about 173 s locally (`.dforge/suites.tsv`, last row for `bash -c node\ scripts/test-all.mjs`, exit 0).

## Task index

1. Record the run's isolation and branch
2. Guard execution on the run's branch
3. Follow the run's isolation at setup and resume
4. Protect carried paths and in-place lanes
5. Ask the worktree question
6. Document and release

---

### Task 1: Record the run's isolation and branch

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh` (`ar_start`'s state literal, `ar_status`; new `ar_setup_branch`, `ar_carried`)
- Modify: `plugins/dforge/scripts/auto-run` (`usage`, the `start` option loop, new `setup-branch` and `carried` cases)
- Create: `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
- Modify: `plugins/dforge/tests/auto-run.test.sh` (the "status: one line" check)
- Modify: `scripts/test-shards.mjs` (weight entry)

**Interfaces:**
- Consumes: none
- Produces: C1, C2, C3, C4, C8

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh` (mode 755):

```bash
#!/usr/bin/env bash
# Acceptance checks for docs/dforge/specs/2026-11-08-auto-run-worktree-setting-design.md:
# an auto run follows the worktree setting, guards its own branch and never
# commits the changes it carried into an in-place run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
S="$P/scripts"
AR="$S/auto-run"
TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export LC_ALL=C MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
REPO="$TMP/repo"
STATE="$REPO/.dforge/sdd/auto-run.json"
SPEC=docs/dforge/specs/2026-11-08-widget-design.md

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
beat() { # beat <session>: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
}
arun() { # arun <dir> <session> <args...>
  local dir=$1 s=$2
  shift 2
  beat "$s"
  (cd "$dir" && bash "$AR" --session "$s" "$@")
}
field() { jq -r --arg f "$1" '.[$f] | tostring' < "$STATE" | tr -d '\r'; }
fresh() { # a new repository on main with two tracked files and no run
  rm -rf "$REPO" "$TMP/side"
  git init -q -b main "$REPO"
  printf 'one\n' > "$REPO/a.txt"
  printf 'two\n' > "$REPO/b.txt"
  git -C "$REPO" add a.txt b.txt
  git -C "$REPO" commit -qm init
}
inplace() { # inplace <session>: an in-place run on its recorded branch auto/widget
  fresh
  arun "$REPO" "$1" start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
  git -C "$REPO" switch -q -c auto/widget
  arun "$REPO" "$1" setup-branch auto/widget >/dev/null
}

# --- Task 1 ---
fresh
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null; status=$?
check "A1: start --isolation in-place exits 0" "$status" "0"
check "A1: the state records in-place" "$(field isolation)" "in-place"
has "A1: status prints the isolation" "$(arun "$REPO" t1 status)" "isolation in-place"
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
has "A2: a start without --isolation reads as worktree" "$(arun "$REPO" t1 status)" "isolation worktree"
jq 'del(.isolation)' < "$STATE" > "$TMP/state.json" && mv "$TMP/state.json" "$STATE"
has "A2: a state file without the field reads as worktree" "$(arun "$REPO" t1 status)" "isolation worktree"
rm -f "$STATE"
out=$(arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation elsewhere 2>&1); status=$?
check "A3: an unknown isolation exits 2" "$status" "2"
has "A3: and says which values it takes" "$out" "auto-run: --isolation must be worktree or in-place"
check "A3: and writes no state file" "$([ -e "$STATE" ] && echo yes || echo no)" "no"

fresh
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
arun "$REPO" t1 setup-branch main >/dev/null 2>&1; status=$?
check "A9: setup-branch refuses the base as the run's branch" "$status:$(field branch)" "4:null"
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t1 setup-branch auto/other >/dev/null 2>&1; status=$?
check "A9: setup-branch refuses a branch HEAD is not on" "$status:$(field branch)" "4:null"
printf 'mine\n' >> "$REPO/a.txt"
mv "$REPO/b.txt" "$REPO/c.txt"
git -C "$REPO" add -N c.txt
mkdir -p "$REPO/notes"
printf 'x\n' > "$REPO/notes/n1.md"
printf 'y\n' > "$REPO/notes/n2.md"
arun "$REPO" t1 setup-branch auto/widget >/dev/null; status=$?
check "A9: setup-branch on the run's branch exits 0" "$status" "0"
check "A9: it records the branch" "$(field branch)" "auto/widget"
check "A9: it records the branch's start commit" "$(field branchBase)" "$(git -C "$REPO" rev-parse HEAD)"
check "A9: carried holds each modified, worktree-renamed (both sides) and untracked file" \
  "$(arun "$REPO" t1 carried | tr -d '\r' | sort | tr '\n' ' ')" "a.txt b.txt c.txt notes/n1.md notes/n2.md "
has "A9: status names the branch" "$(arun "$REPO" t1 status)" "branch auto/widget"

fresh
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
printf 'staged\n' >> "$REPO/a.txt"
git -C "$REPO" add a.txt
out=$(arun "$REPO" t1 setup-branch auto/widget 2>&1); status=$?
check "A21: staged changes: exit 4, nothing recorded" "$status:$(field branch):$(field carried)" "4:null:null"
has "A21: the refusal names the staged path" "$out" "auto-run: staged changes in the primary checkout: a.txt"

# --- summary ---
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

Add `'auto-run-worktree-setting.acceptance.test.sh': 150,` to `windowsSeconds` in `scripts/test-shards.mjs`, in alphabetical order.

In `plugins/dforge/tests/auto-run.test.sh`, the check "status: one line" (line 88): append ` — isolation worktree` to its expected line, after `register $reg`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
Expected: FAIL — `start` rejects `--isolation` as a usage error, `setup-branch` and `carried` are unknown commands.

- [ ] **Step 3: Implement**

1. `scripts/auto-run` `start)`: accept `--isolation <v>`; after the loop, when given and not `worktree` or `in-place`, print C2's message and exit 2 before calling `ar_start`. Pass the value (default `worktree`) as a fourth argument. Add `setup-branch NAME` (exactly one argument, `bound`, `ar_setup_branch "$1"`) and `carried` (no arguments, `bound`, `ar_carried`). Add both and the flag to `usage`.
2. `ar_start SPEC REGISTER FORCE ISOLATION`: add `isolation: $iso, branch: null, branchBase: null, carried: null` to the state literal.
3. `ar_status`: append C4's parts, reading `(.isolation // "worktree")` and `.branch`.
4. `ar_setup_branch NAME`: apply C3's three refusals in that order, then record through `ar_update`. Parse `git status --porcelain=v1 -z --untracked-files=all`: each entry is `XY path`, and an entry with `X` or `Y` of `R` or `C` is followed by one more NUL-terminated field, the original path; record both. Build the `carried` array with `jq -R`/`--argjson`, not by string splicing, so a path with spaces stays one entry.
5. `ar_carried`: print `.carried[]?`, one per line.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh && timeout 900 bash plugins/dforge/tests/auto-run.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS, `0 failed` in both suites.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/auto-run plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh plugins/dforge/tests/auto-run.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): record an auto run's isolation"
```

### Task 2: Guard execution on the run's branch

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh` (`ar_in_primary`'s comment, new `ar_guard` and `ar_carried_hit`, `ar_set_phase`, `ar_task_complete`, the comment above `ar_switch`)
- Modify: `plugins/dforge/scripts/auto-run` (the "setup due" hint), `plugins/dforge/scripts/next-step` (the "No ledger exists yet" prompt)
- Modify: `plugins/dforge/tests/auto-run.test.sh` (the linked-worktree pin at its "a run started in a linked worktree" check), `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`, and any `tests/next-step*.test.sh` pin of "worktree first"

**Interfaces:**
- Consumes: C1, C3, C8 (Task 1)
- Produces: C5, C6

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 3 = 8

- [ ] **Step 1: Extend the test `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`**

Append above `# --- summary ---`:

```bash
# --- Task 2 ---
fresh
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
out=$(arun "$REPO" t2 phase execute 2>&1); status=$?
check "A4: phase execute on the base in the primary checkout: exit 4, phase unchanged" "$status:$(field phase)" "4:spec"
has "A4: the refusal points at Step 0" "$out" "follow dforge:using-git-worktrees Step 0 for the run"
git -C "$REPO" worktree add -q -b side "$TMP/side"
arun "$TMP/side" t2 start --spec "$SPEC" --register docs/r.md --isolation worktree --force >/dev/null
check "A4: a run started in a linked worktree takes its branch as base" "$(field base)" "side"
arun "$TMP/side" t2 phase execute >/dev/null 2>&1; status=$?
check "A4: phase execute on the base in a linked worktree: exit 4" "$status:$(field phase)" "4:spec"
git -C "$TMP/side" switch -q -c auto/widget
arun "$TMP/side" t2 setup-branch auto/widget >/dev/null
arun "$TMP/side" t2 phase execute; status=$?
check "A12: a linked-worktree run reaches execute on its own branch" "$status:$(field phase)" "0:execute"

inplace t2
arun "$REPO" t2 phase execute; status=$?
check "A5: in place on the recorded branch: exit 0" "$status:$(field phase)" "0:execute"
git -C "$REPO" switch -q -c elsewhere
arun "$REPO" t2 phase execute >/dev/null 2>&1; status=$?
check "A6: phase execute off the recorded branch: exit 4" "$status" "4"
out=$(arun "$REPO" t2 task-complete 2>&1); status=$?
check "A6: task-complete off the recorded branch stops the run" "$status:$(field active)" "5:false"
has "A6: and says why" "$out" "a task was completed off the run's branch"

fresh
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation worktree >/dev/null
git -C "$REPO" switch -q -c feature
out=$(arun "$REPO" t2 phase execute 2>&1); status=$?
check "A7: a worktree run in the primary checkout: exit 4 off the base too" "$status:$(field phase)" "4:spec"
has "A7: with today's message" "$out" "create the execution worktree first (dforge:using-git-worktrees)"

fresh
git -C "$REPO" switch -q --detach
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
check "A8: a detached start has no base" "$(field base)" "null"
arun "$REPO" t2 phase execute >/dev/null 2>&1; status=$?
check "A8: detached in the primary checkout with no base: exit 4" "$status" "4"
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute; status=$?
check "A8: on the recorded branch: exit 0" "$status" "0"
fresh
git -C "$REPO" worktree add -q --detach "$TMP/side"
arun "$TMP/side" t2 start --spec "$SPEC" --register docs/r.md --isolation worktree >/dev/null
arun "$TMP/side" t2 phase execute >/dev/null 2>&1; status=$?
check "A8: detached in a linked worktree with no base: exit 4" "$status:$(field phase)" "4:spec"
git -C "$TMP/side" switch -q -c auto/widget
arun "$TMP/side" t2 setup-branch auto/widget >/dev/null
arun "$TMP/side" t2 phase execute; status=$?
check "A8: that worktree on the recorded branch: exit 0" "$status" "0"

fresh
printf 'mine\n' >> "$REPO/a.txt"
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute
printf 'task\n' > "$REPO/t.txt"
git -C "$REPO" add t.txt && git -C "$REPO" commit -qm task
arun "$REPO" t2 task-complete; status=$?
check "A10: a commit of other paths: task-complete exits 0" "$status:$(field active)" "0:true"
arun "$REPO" t2 phase final; status=$?
check "A20: phase final with no carried path committed: exit 0" "$status:$(field phase)" "0:final"
arun "$REPO" t2 phase finish; status=$?
check "A20: phase finish with no carried path committed: exit 0" "$status:$(field phase)" "0:finish"
arun "$REPO" t2 phase final >/dev/null
git -C "$REPO" add a.txt && git -C "$REPO" commit -qm carried
out=$(arun "$REPO" t2 phase finish 2>&1); status=$?
check "A20: phase finish after a carried path was committed: exit 4" "$status:$(field phase)" "4:final"
has "A20: names the path" "$out" "auto-run: carried path a.txt was committed; stop the run"
out=$(arun "$REPO" t2 task-complete 2>&1); status=$?
check "A10: task-complete after a carried path was committed stops the run" "$status:$(field active)" "5:false"
has "A10: the stop reason names the path" "$out" "carried path a.txt was committed"

fresh
printf 'mine\n' >> "$REPO/a.txt"
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute
git -C "$REPO" add a.txt && git -C "$REPO" commit -qm carried
out=$(arun "$REPO" t2 phase final 2>&1); status=$?
check "A20: phase final after a carried path was committed: exit 4" "$status:$(field phase)" "4:execute"

fresh
printf 'mine\n' >> "$REPO/a.txt"
printf 'draft\n' > "$REPO/draft.md"
before=$(cd "$REPO" && git hash-object a.txt draft.md | tr -d '\r' | tr '\n' ' ')
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute
printf 'task\n' > "$REPO/t.txt"
git -C "$REPO" add t.txt && git -C "$REPO" commit -qm task
arun "$REPO" t2 task-complete; status=$?
git -C "$REPO" switch -q main
git -C "$REPO" merge -q --no-edit auto/widget
git -C "$REPO" branch -q -d auto/widget
check "A11: the flow's task-complete passed" "$status" "0"
check "A11: carried files are byte for byte unchanged" "$(cd "$REPO" && git hash-object a.txt draft.md | tr -d '\r' | tr '\n' ' ')" "$before"
check "A11: and still uncommitted" "$(git -C "$REPO" status --porcelain | tr -d '\r' | sort | tr '\n' '|')" " M a.txt|?? draft.md|"
check "A11: the task's commit reached main" "$(git -C "$REPO" log -1 --format=%s -- t.txt)" "task"
check "A11: the run's branch is deleted" "$(git -C "$REPO" branch --list auto/widget)" ""
```

In `plugins/dforge/tests/auto-run.test.sh`, at the check named "a run started in a linked worktree: phase execute there passes": the run's base is `side`, so change its expectation to exit 4 with the phase unchanged, rename it "a run started in a linked worktree: phase execute on its base is refused", then add `git -C "$TMP/side" switch -q -c auto/side-run`, `side --session s-5 setup-branch auto/side-run` and the original check (exit 0, phase `execute`) under the name "a run started in a linked worktree: phase execute on its own branch passes". Switch `$TMP/side` back with `git -C "$TMP/side" switch -q side` right after, so the suite's later `side` calls run on the branch they ran on before. The checks "after a switch, continue names Setup" (line 633) and "after-compact: an unknown size with setup due names Setup" (line 729): change `worktree first` to `workspace first` in their expected text. Leave lines 181-182 and 645-646 unchanged: C5's precedence keeps them passing.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
Expected: FAIL on the A4 linked-worktree, A5, A6, A8, A10 and A20 checks (the guard still tests the primary checkout only).

- [ ] **Step 3: Implement**

1. `ar_guard`: return 0 (refuse) per C5's three rules in C5's precedence order, setting a variable or printing a rule number the callers use to pick the message and the stop reason. Keep `ar_in_primary` for rule (3) and update its comment: it now guards worktree runs only.
2. `ar_carried_hit`: print C6's first hit; nothing and return 1 when `branchBase` is null or nothing matches. Compare paths exactly (read both lists line by line; no regular expressions, since a path may contain `.` or `[`).
3. `ar_set_phase`: for `execute`, refuse on `ar_guard` with C5's message for the rule; for `final` and `finish`, refuse on `ar_carried_hit` with C6's message. All refusals exit 4 before `ar_update`.
4. `ar_task_complete`: in the execute or final phase, stop on `ar_guard` with C6's reason for the rule; in any phase, stop on `ar_carried_hit` with `carried path <p> was committed`. Keep the stderr line's form.
5. Wording: the "setup due" hint in `scripts/auto-run` and the prompt in `scripts/next-step` say `workspace first` instead of `worktree first`; the comment above `ar_switch` says "a phase execute from the execution workspace". Update any `tests/next-step*.test.sh` pin of the old phrase.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh && timeout 900 bash plugins/dforge/tests/auto-run.test.sh && timeout 1500 node scripts/test-all.mjs`
Expected: PASS, `0 failed` in both suites; test-all exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/auto-run plugins/dforge/scripts/next-step plugins/dforge/tests/
git commit -m "feat(dforge): guard an auto run on its own branch"
```

### Task 3: Follow the run's isolation at setup and resume

**Files:**
- Modify: `plugins/dforge/skills/using-git-worktrees/SKILL.md` (Step 0's auto-run paragraph, the sandbox fallback's auto-run sentence)
- Modify: `plugins/dforge/skills/resume-execution/SKILL.md` (steps 2 and 3)
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (the auto-run Setup bullet and its exit-4 remedy; "outside this worktree")
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (the auto-run Setup bullet; "outside this worktree")
- Modify: `plugins/dforge/reference/auto-run.md` (§Skipped questions, the side-effect sentence, §The switch's Setup sentence, §Stopping)
- Modify: `plugins/dforge/tests/auto-run-skills.test.sh` (the pins that name the old sentences), `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`

**Interfaces:**
- Consumes: C3, C5, C7 (Tasks 1-2)
- Produces: none

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`**

Append above `# --- summary ---`:

```bash
# --- Task 3 ---
G="$P/skills/using-git-worktrees/SKILL.md"
present "A13: Step 0 reads the run state" "$G" 'read the auto-run state (`scripts/auto-run status`), not the `worktree` setting'
present "A13: a recorded branch is switched back to" "$G" 'When the status names `branch <name>`, switch to that branch'
present "A13: a base or detached HEAD gets the run's branch" "$G" '`git switch -c auto/<plan slug>`'
present "A13: setup-branch records it" "$G" '`scripts/auto-run setup-branch <name>`'
present "A13: staged changes stop the run" "$G" 'staged changes in the primary checkout: <paths>'
present "A13: a worktree run in the primary checkout creates it unasked" "$G" 'Under `isolation worktree` in the primary checkout, create the worktree without asking'
check "A15: no skill says never creates the worktree in an auto run" \
  "$(grep -rlF -- '`worktree=never` creates' "$P/skills" "$P/reference" | wc -l | tr -d ' ')" "0"
R="$P/skills/resume-execution/SKILL.md"
present "A19: resume switches back to the run's branch" "$R" 'When HEAD is not on it, run `git switch <name>`'
present "A19: a gone branch stops the run" "$R" "the run's branch <name> is gone"
present "A19: no EnterWorktree into the primary checkout" "$R" 'Skip EnterWorktree when the recorded workspace is the primary checkout'
present "A19: auto-run.md lists the stop" "$P/reference/auto-run.md" "the run's branch is gone"
present "auto-run.md: the worktree consent is asked under ask" "$P/reference/auto-run.md" 'the worktree consent (asked at the spec review under `worktree=ask`)'
for f in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md" "$P/reference/auto-run.md"; do
  absent "$(basename "$(dirname "$f")")/$(basename "$f"): no execution worktree wording" "$f" 'from the execution worktree'
  present "$(basename "$(dirname "$f")")/$(basename "$f"): side effects outside the workspace" "$f" 'outside the execution workspace'
done
present "executing-plans: Setup runs from the workspace" "$P/skills/executing-plans/SKILL.md" 'from the execution workspace'
present "executing-plans: exit 4 points at Step 0" "$P/skills/executing-plans/SKILL.md" 'follow dforge:using-git-worktrees Step 0 for the run, then run the command again'
present "subagent-driven-development: exit 4 points at Step 0" "$P/skills/subagent-driven-development/SKILL.md" 'follow dforge:using-git-worktrees Step 0 for the run, then run the command again'
for f in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md"; do
  present "$(basename "$(dirname "$f")"): exit 5 names every stop" "$f" 'on the run base, off its branch or in the primary checkout, or a carried path was committed'
done
present "auto-run.md: the switch starts at Setup, workspace first" "$P/reference/auto-run.md" 'execution skill starts at its Setup, workspace first: `scripts/auto-run status`'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
Expected: FAIL on every Task 3 check, A15 included (the current text still says "`worktree=never` creates it too").

- [ ] **Step 3: Implement**

1. using-git-worktrees Step 0: replace the auto-run paragraph ("In an auto run … `worktree=never` creates it too …") with one that, in an auto run, says to read the auto-run state (`scripts/auto-run status`), not the `worktree` setting, before the "already in a linked worktree" check, in any checkout: when the status names `branch <name>`, switch to that branch if HEAD is elsewhere, then go to Step 2; when no branch is recorded and HEAD is the run's base or detached, under `isolation in-place` (or in a linked worktree under either isolation) run `` `git switch -c auto/<plan slug>` `` with C7's slug and suffix, then `` `scripts/auto-run setup-branch <name>` ``, carrying unstaged and untracked changes; on its staged-changes refusal run `scripts/auto-run stop --reason "staged changes in the primary checkout: <paths>"` and end as auto-run.md §Stopping says; under `isolation worktree` in the primary checkout, create the worktree without asking (Step 1). The sandbox fallback's auto-run sentence applies under `isolation worktree` only. The attended text below the paragraph is unchanged.
2. resume-execution step 2: add, for an auto run whose status names `branch <name>`: when `git branch --list <name>` prints nothing, run `scripts/auto-run stop --reason "the run's branch <name> is gone"` and ask; when HEAD is not on it, run `git switch <name>`; a refused switch stops the run the same way. Step 3: skip EnterWorktree when the recorded workspace is the primary checkout.
3. executing-plans and subagent-driven-development: the auto-run Setup bullet runs `scripts/auto-run phase execute` from the execution workspace (the worktree, or the checkout on the run's branch) once dforge:using-git-worktrees Step 0 has prepared it; in both skills the exit-4 remedy ("Exit 4 means the worktree step was skipped: create the worktree, then run the command again from it." in subagent-driven-development, and its counterpart in executing-plans) reads "Exit 4 means the workspace step was skipped: follow dforge:using-git-worktrees Step 0 for the run, then run the command again". In both, "A `task-complete` exit 5 means the run stopped (a task was completed in the primary checkout)" becomes "A `task-complete` exit 5 means the run stopped (a task was completed on the run base, off its branch or in the primary checkout, or a carried path was committed)". "a side effect outside this worktree" becomes "a side effect outside the execution workspace" in both.
4. auto-run.md: §Skipped questions names "the worktree consent (asked at the spec review under `worktree=ask`)"; the sentence about "a side effect outside the worktree" says "outside the execution workspace"; §The switch's "execution skill starts at its Setup, worktree first: `scripts/auto-run status`" becomes "execution skill starts at its Setup, workspace first: `scripts/auto-run status`", and its "runs from the execution worktree" becomes "runs from the execution workspace"; §Stopping adds "the run's branch is gone" beside the gone-worktree case.
5. `tests/auto-run-skills.test.sh`: repoint the pins at lines 30 ("from the execution worktree, once dforge:using-git-worktrees has created it." → "from the execution workspace"), 109 (→ "execution skill starts at its Setup, workspace first: `scripts/auto-run status`"), 122 ("`worktree=never` creates it too" → "read the auto-run state (`scripts/auto-run status`), not the `worktree` setting") and 123 (the sandbox sentence → its new wording under `isolation worktree`).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh && timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh && timeout 1500 node scripts/test-all.mjs`
Expected: PASS, `0 failed`; test-all exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/using-git-worktrees/SKILL.md plugins/dforge/skills/resume-execution/SKILL.md plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/reference/auto-run.md plugins/dforge/tests/
git commit -m "feat(dforge): set up auto runs by their isolation"
```

### Task 4: Protect carried paths and in-place lanes

**Files:**
- Modify: `plugins/dforge/skills/executing-plans/references/recovery.md` (the `fix round R/3 (…; passing)` row), `plugins/dforge/skills/executing-plans/references/setup.md` (staging rule), `plugins/dforge/skills/executing-plans/SKILL.md` and `plugins/dforge/skills/subagent-driven-development/SKILL.md` (each step that runs `scripts/auto-run phase final`)
- Modify: `plugins/dforge/reference/final-review.md` (the QA timeout cleanup and the startup cleanup that reads `qa-status-before.txt`)
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (§Auto run: the stop list, the merged-result note, the in-place final-message line, the `phase finish` refusal)
- Modify: `plugins/dforge/reference/executor-lane.md` (§Reserve an exclusive linked worktree), `plugins/dforge/skills/writing-plans/references/auto-run-plan.md` (the executor offer bullet)
- Modify: `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`

**Interfaces:**
- Consumes: C3 (`scripts/auto-run carried`), C6, C10
- Produces: none

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`**

Append above `# --- summary ---`:

```bash
# --- Task 4 ---
X="$P/reference/executor-lane.md"
present "A16: the lane falls back in the primary checkout" "$X" 'executor <id> unavailable - no linked worktree'
present "A16: after the plain task-step start" "$X" 'run `task-step start` as the executor path does'
present "A16: users keep the primary checkout only in worktree runs" "$X" 'In a worktree run the user can continue in the primary checkout'
present "A16: the auto-run offer ticks nothing in place" "$P/skills/writing-plans/references/auto-run-plan.md" 'tick nothing when `scripts/auto-run status` prints `isolation in-place`'
present "A17: recovery leaves carried paths uncommitted" "$P/skills/executing-plans/references/recovery.md" 'commit anything uncommitted except the carried paths (`scripts/auto-run carried`)'
present "A17: QA cleanup never touches a carried path" "$P/reference/final-review.md" 'Never restore or delete a carried path (`scripts/auto-run carried`)'
present "A17: tasks stage by name" "$P/skills/executing-plans/references/setup.md" 'stage the paths it changed by name, never `git add -A` or `git add .`'
stray=$(cat "$P/skills/executing-plans/SKILL.md" "$P"/skills/executing-plans/references/*.md "$P/skills/subagent-driven-development/SKILL.md" \
  "$P/reference/auto-run.md" "$P/reference/delegated-task.md" "$P/skills/using-git-worktrees/SKILL.md" \
  | grep -E 'git add (-A|\.)([ `]|$)' | grep -vcF 'never `git add -A` or `git add .`')
check "A17: no auto-run setup or task-loop text stages everything" "$stray" "0"
present "executing-plans: a carried commit at phase final stops the run" "$P/skills/executing-plans/SKILL.md" 'is a carried path and was committed'
present "subagent-driven-development: a carried commit at phase final stops the run" "$P/skills/subagent-driven-development/SKILL.md" 'is a carried path and was committed'
F="$P/skills/finishing-a-development-branch/SKILL.md"
present "A18: the stop list names checkout, pull and merge" "$F" 'a refused checkout, pull or merge of the base'
present "A18: phase finish refusal stops the run" "$F" 'is a carried path and was committed'
present "A18: a red merged suite lists the carried paths" "$F" 'list the carried paths (`scripts/auto-run carried`) with the failure'
present "A18: pr and keep name the branch" "$F" 'This checkout is on `auto/<slug>`; your uncommitted changes are here'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
Expected: FAIL on every Task 4 `present` check.

- [ ] **Step 3: Implement**

1. recovery.md, the `fix round R/3 (…; passing)` row: "commit anything uncommitted except the carried paths (`scripts/auto-run carried`)".
2. setup.md: in an in-place auto run, every task, fix round and QA commit stage the paths it changed by name, never `git add -A` or `git add .`; a change the task needs to a carried path stops the run with `scripts/auto-run stop --reason "<task> needs carried path <path>"`.
3. executing-plans SKILL.md and subagent-driven-development SKILL.md, at each step that runs `scripts/auto-run phase final`: on exit 4, run `scripts/auto-run stop --reason "<path> is a carried path and was committed"` and end as auto-run.md §Stopping says.
4. final-review.md, both cleanups that restore or delete what `qa-status-before.txt` lacks: "Never restore or delete a carried path (`scripts/auto-run carried`), whatever its status line shows."
5. finishing SKILL.md §Auto run: the stop list (where it names "a rejected push, a refused worktree removal") adds "a refused checkout, pull or merge of the base"; `scripts/auto-run phase finish` exiting 4 runs `scripts/auto-run stop --reason "<path> is a carried path and was committed"`; in an in-place run, a red merged-result suite is reported to list the carried paths (`scripts/auto-run carried`) with the failure; for `pr` and `keep` in an in-place run the final message carries the line "This checkout is on `auto/<slug>`; your uncommitted changes are here".
6. executor-lane.md §Reserve an exclusive linked worktree: in the primary checkout, run `task-step start` as the executor path does (it needs no linked worktree), then neither the gate nor the wrapper; fall back to the session review loop as the unavailable-executor fallback describes, recording C10's line. "The user can continue in the primary checkout." becomes "In a worktree run the user can continue in the primary checkout."
7. auto-run-plan.md, the executor offer bullet: add "tick nothing when `scripts/auto-run status` prints `isolation in-place`".

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh && timeout 1500 node scripts/test-all.mjs`
Expected: PASS, `0 failed`; test-all exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/executing-plans/ plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/reference/final-review.md plugins/dforge/reference/executor-lane.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/skills/writing-plans/references/auto-run-plan.md plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh
git commit -m "feat(dforge): protect carried paths in place"
```

### Task 5: Ask the worktree question

**Files:**
- Modify: `plugins/dforge/skills/brainstorming/references/auto-by-default.md` (step 5's question list, step 6's start command)
- Modify: `plugins/dforge/skills/brainstorming/references/auto-run-offer.md` (the offer block and its start command)
- Modify: `plugins/dforge/reference/auto-run.md` (§Starting's start command)
- Modify: `plugins/dforge/config/schema.mjs` (`worktree.description`)
- Modify: `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`, and any `tests/settings-skills.test.sh` or `tests/dforge-config.test.sh` pin of the old description

**Interfaces:**
- Consumes: C2, C9
- Produces: none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Extend the test `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`**

Append above `# --- summary ---`:

```bash
# --- Task 5 ---
D="$P/skills/brainstorming/references/auto-by-default.md"
present "A14: the spec review asks under ask only" "$D" 'when the `worktree` setting is `ask`'
present "A14: in the last call beside the approval" "$D" 'in the last call, beside the approval question'
present "A14: the worktree option" "$D" '**Isolated worktree (Recommended)**'
present "A14: the in-place option" "$D" '**Work in place on a new branch — leave this checkout alone until the run finishes**'
present "A14: the Decisions line" "$D" '`Worktree: <worktree|in-place>`'
present "A14: step 6 passes the isolation" "$D" 'passes `--isolation <worktree|in-place>`'
O="$P/skills/brainstorming/references/auto-run-offer.md"
present "A14: offer option 1" "$O" '1. Yes, in an isolated worktree'
present "A14: offer option 2" "$O" '2. Yes, in place on a new branch (leave this checkout alone until the run finishes)'
present "A14: offer option 3" "$O" '3. No, keep the normal stops'
present "A14: the offer passes in-place" "$O" '--isolation in-place'
present "auto-run.md: start names the flag" "$P/reference/auto-run.md" '--isolation <worktree|in-place>'
present "schema: the worktree setting names auto runs" "$P/config/schema.mjs" 'an auto run asks at the spec review'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
Expected: FAIL on every Task 5 check.

- [ ] **Step 3: Implement**

1. auto-by-default.md step 5: add a bullet, when the `worktree` setting is `ask` (read as the brainstorming Settings say), asked in the last call, beside the approval question, with the options **Isolated worktree (Recommended)** and **Work in place on a new branch — leave this checkout alone until the run finishes**; record the answer as its own paragraph in `## Decisions`, one `Worktree: <worktree|in-place>` line, as the `Finish:` line is. Step 6: the start command passes `--isolation <worktree|in-place>`: the `Worktree:` line's value under `ask`, `worktree` under `always`, `in-place` under `never`, and a user instruction naming a preference outranks the setting.
2. auto-run-offer.md: under `worktree=ask` the offer block has the three options the test names (1 and 2 start the run with `--isolation worktree` and `--isolation in-place`, 3 continues without a run); under `always` or `never` it keeps its two options and passes the setting's value.
3. auto-run.md §Starting: the start command reads `scripts/auto-run start --spec <spec> --isolation <worktree|in-place>` and says where the value comes from.
4. schema.mjs `worktree.description`: "Whether work is isolated in a git worktree before it starts. ask keeps the consent question; an auto run asks at the spec review."

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh && timeout 1500 node scripts/test-all.mjs`
Expected: PASS, `0 failed`; test-all exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/brainstorming/references/ plugins/dforge/reference/auto-run.md plugins/dforge/config/schema.mjs plugins/dforge/tests/
git commit -m "feat(dforge): ask the worktree question in auto runs"
```

### Task 6: Document and release

**Files:**
- Modify: `plugins/dforge/README.md` (where it describes auto runs and worktrees)
- Modify: `plugins/dforge/.claude-plugin/plugin.json`, `plugins/dforge/.codex-plugin/plugin.json` (`version`)
- Modify: `plugins/dforge/tests/inline-only.acceptance.test.sh` (the "version bumped to 4.13.0" check), `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`

**Interfaces:**
- Consumes: none
- Produces: none

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 0 = 3

- [ ] **Step 1: Extend the test `plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`**

Append above `# --- summary ---`:

```bash
# --- Task 6 ---
present "README: auto runs follow the worktree setting" "$P/README.md" 'An auto run follows the `worktree` setting'
check "release: both manifests at 4.14.0" \
  "$(jq -r .version < "$P/.claude-plugin/plugin.json" | tr -d '\r') $(jq -r .version < "$P/.codex-plugin/plugin.json" | tr -d '\r')" "4.14.0 4.14.0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh`
Expected: FAIL on both Task 6 checks.

- [ ] **Step 3: Implement**

1. README: where it describes the auto run (and the `worktree` setting, if listed), add the sentence "An auto run follows the `worktree` setting: `always` makes the execution worktree unasked, `never` works in this checkout on an `auto/<plan>` branch and leaves your uncommitted changes uncommitted, and `ask` asks at the spec review." Correct any sentence that says an auto run always makes a worktree.
2. Both manifests: `"version": "4.14.0"`.
3. `inline-only.acceptance.test.sh`: replace the "version bumped to 4.13.0" equality with a check that the version sorts at or above 4.13.0 (`printf '4.13.0\n%s\n' "$v" | sort -V | head -n 1` equals `4.13.0`), named "version is 4.13.0 or later".

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh && timeout 120 node scripts/validate-repository.mjs && timeout 1500 node scripts/test-all.mjs`
Expected: PASS, `0 failed`; both node commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json plugins/dforge/tests/
git commit -m "chore(dforge): release 4.14.0"
```
