# Retained Review Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A finished plan leaves `<docs>/reviews/<plan>.md` with its review depth, QA counts, per-lens findings, final review line and test ratio, and every final review writes the per-plan test ratio to the ledger.

**Architecture:** One new script, `scripts/review-record`, with two subcommands: `ratio` prints the `Test ratio:` line from a git range, and `retain` copies the review lines of a plan's ledger into the retained file, finding the ledger in any worktree. The final review reference writes the new ledger lines, finishing's execute-choice reference calls `retain`, and closing-a-milestone lists the ratios; no `SKILL.md` near its size limit changes.

**Tech Stack:** Bash scripts and bash test suites, Markdown references.

**Spec:** docs/dforge/specs/2026-11-10-retained-review-data-design.md

**Execution:** inline — `claude --model opus --effort high` — the hardest task totals 6

**Parallelism:** sequential — inline execution

**Task check:** `timeout 1500 node scripts/test-all.mjs` — the full suite last passed in 173 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-11 — dforge:judge-opus — executability 16 / coherence 17 / coverage 16 / assumptions 14 (round 1)

## Global Constraints

- English only in code, comments, docs, commits and tests.
- Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, authored as `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind.
- No code comment unless the why is non-obvious; never reference this task or plan in a comment.
- Nothing is pushed before finishing.
- Every `skills/*/SKILL.md` stays at or under 20,000 bytes (`tests/speed-and-cost.acceptance.test.sh`); this plan edits no `SKILL.md` except `skills/closing-a-milestone/SKILL.md` (6,834 bytes).
- No test checks the wording of a skill or reference (register row 12); the reference edits are carried by spec statements A10-A12, which are `demo`.
- Windows Git Bash: A native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: The same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: Files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): A lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **Script:** `plugins/dforge/scripts/review-record`, run as `bash <plugin-root>/scripts/review-record <subcommand> …`. It sources `lib/roots.sh` and `lib/plan.sh`.
- **`review-record ratio MERGE_BASE HEAD`:** prints exactly one line to stdout and writes nothing: `Test ratio: <t> test / <c> code lines (<base7>..<head7>)`, where `<base7>` and `<head7>` are `git rev-parse --short=7` of the two revisions. Exit 0 printed; exit 2 for usage, an unknown revision, or a test-quality lens with no `paths` clause, printing nothing to stdout and one `review-record: <reason>` line to stderr.
- **Test lens path:** `ratio` reads the `Applies:` line of `<plugin-root>/criteria/lenses/test-quality.md`, where `<plugin-root>` is the script's own directory's parent.
- **`review-record retain PLAN_FILE [--from CHECKOUT]`:** writes `<docs>/reviews/<plan-basename>.md`, `<docs>` being `dforge_docs_root` of the current directory, and prints that absolute path. Exit 0 written; 2 usage; 3 the ledger holds no selected line, nothing written, one stderr line `review-record: <plan name> has no review lines in <ledger>`; 4 no ledger found, nothing written, stderr `review-record: no ledger for <plan name>; searched:` followed by one searched `progress.md` path per line.
- **Selected ledger lines:** after stripping `\r`, the lines beginning `Review depth:`, `Acceptance QA: complete`, `Acceptance QA: skipped`, `final review lens`, `Final review:` or `Test ratio:`, verbatim and in ledger order.
- **Retained file format:**

  ```markdown
  # Review record: <plan-basename>

  Plan: <dforge_name of PLAN_FILE>
  Retained: <YYYY-MM-DD>

  <selected lines>
  ```

- **New ledger lines** (written by the final review, Task 3): `final review lens <id> — <c> Critical, <i> Important, <m> Minor; fixed <f>, rejected <r>`; `final review lenses off`; the `Test ratio:` line above.

## Assumptions (evidence)

- The worktree's ledger exists when Step 5b runs on Option 1: `plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md` records the plan after the merge and before cleanup, and `references/cleanup.md` removes the worktree only in Step 6 (read 2026-11-10). Reading it from the main checkout is unverified — Task 1 verifies it (its `--from` and fallback checks).
- A ledger's first line is `# SDD ledger — plan: <plan path>`: `ledger_plan` in `plugins/dforge/scripts/lib/plan.sh:68-70`.
- `dforge_ledger_dir SLUG DIR` gives `<DIR's state>/sdd/<SLUG>` with local progress and the mirror's directory under darkmem; `dforge_docs_root [DIR]` and `dforge_name PATH [DIR]` resolve per checkout: `plugins/dforge/scripts/lib/roots.sh:94-99,200`, exercised by `plugins/dforge/tests/roots.test.sh`.
- The test-quality lens's `Applies:` line is `paths *tests/* *test/* *__tests__/* *.test.* *_test.* *.spec.* *test_*.py`, and its globs are bash `case` patterns where `*` crosses `/`: `plugins/dforge/criteria/lenses/test-quality.md:3`, `plugins/dforge/scripts/lens-route:65-100` (read 2026-11-10).
- `scripts/test-all.mjs` discovers `plugins/dforge/tests/*.test.sh` itself, and `scripts/test-shards.mjs` `checkShellWeights` requires a `windowsSeconds` entry for each shell suite: `scripts/test-shards.mjs:36,158-176`.
- `reviews/` is not a reserved docs directory, so the darkmem mirror syncs it: `RESERVED_DIRS` in `plugins/dforge/scripts/lib/darkmem-mirror.mjs:20` holds only `handoff` and `archive`.
- Finishing captures `WORKTREE_PATH=$(git rev-parse --show-toplevel)` in Step 2, before Step 5 changes directory: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md:121-123`.
- The final review's reports are `<workspace>/final-fix-report.md` (with `REJECTED: <finding>` lines), `<workspace>/final-rereview-report.md` and the dedupe report's `CONFIRMED`/`REJECTED` marks: `plugins/dforge/reference/final-review.md:324-330,389-393,401`. The fix report carries no lens tag today; Task 3 adds the requirement.
- `ratio`'s rule excluding a `<docs>` root inside the repository but outside `docs/` is deliberately untested: no acceptance statement names it, and every fixture's docs root is `docs/dforge`, which the `docs/` rule already covers.
- Tasks 3 and 4 use the Step 1 form `No new test, because <reason>`, which register row 6 accepted on 2026-11-10 and which `plan-lint` does not yet recognize; it raises nothing for an unrecognized Step 1 heading (`plugins/dforge/scripts/plan-lint`, Step 1 forms section). Their result is the agent behaviour that spec statements A10-A12 describe, which only a finished plan shows, so rows 2 and 3 close as `verify`.

## Task index

1. Retain a plan's review lines
2. Compute the per-plan test ratio
3. Write the review lines in the final review
4. Call retain at finishing and list ratios at closing

---

### Task 1: Retain a plan's review lines

**Files:**
- Create: `plugins/dforge/scripts/review-record`
- Create: `plugins/dforge/tests/review-record.test.sh`
- Modify: `scripts/test-shards.mjs` (the `windowsSeconds` table)

**Interfaces:**
- Consumes: none
- Produces: the Script, `retain`, Selected ledger lines and Retained file format entries of Contracts

**Items:** 3
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/review-record.test.sh`:

```bash
#!/usr/bin/env bash
# scripts/review-record: the retained review record a finished plan leaves,
# and the per-plan test ratio its final review writes to the ledger.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DFORGE_DOCUMENT_STORE DFORGE_PROGRESS_SOURCE CLAUDE_PROJECT_DIR

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
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

ledger() { # ledger <checkout> <slug> <plan named> <line>...
  local dir="$1/.dforge/sdd/$2" named=$3
  shift 3
  mkdir -p "$dir"
  { printf '# SDD ledger — plan: %s\n' "$named"; printf '%s\n' "$@"; } > "$dir/progress.md"
}
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

# --- retain ---
REPO="$TMP/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/docs/dforge/plans"
printf '# P\n' > "$REPO/docs/dforge/plans/2026-01-01-p.md"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m init
TOP=$(git -C "$REPO" rev-parse --show-toplevel)
git -C "$REPO" worktree add -q -b wt "$TMP/wt"
WT=$(git -C "$TMP/wt" rev-parse --show-toplevel)
PLAN="$TOP/docs/dforge/plans/2026-01-01-p.md"
REVIEW="$TOP/docs/dforge/reviews/2026-01-01-p.md"

ledger "$WT" 2026-01-01-p "$WT/docs/dforge/plans/2026-01-01-p.md" \
  'Review depth: standard (interface)' \
  'Task 1: complete (commits abc1234..bcd2345) — discovered: none' \
  'Acceptance QA: dispatched (base abc1234)' \
  'Ruling: Task 2 reworded — a reason — none' \
  'Acceptance QA: complete — 5 pass, 0 fail, 0 flaky, 0 cannot-test, 1 demo' \
  'final review lens-skipped docs-comments reason=cap' \
  'final review lens security — 0 Critical, 1 Important, 2 Minor; fixed 1, rejected 1' \
  'Test ratio: 40 test / 100 code lines (abc1234..def5678)' \
  'Final review: clean (commits abc1234..def5678)'
mkdir -p "$TOP/docs/dforge/plans/old"
printf '# Old\n' > "$TOP/docs/dforge/plans/old/2026-01-01-p.md"
ledger "$TOP" 2026-01-01-p "$TOP/docs/dforge/plans/old/2026-01-01-p.md" 'Review depth: full (risk)'

want=$(printf '%s\n' '# Review record: 2026-01-01-p' '' \
  'Plan: docs/dforge/plans/2026-01-01-p.md' "Retained: $(date +%Y-%m-%d)" '' \
  'Review depth: standard (interface)' \
  'Acceptance QA: complete — 5 pass, 0 fail, 0 flaky, 0 cannot-test, 1 demo' \
  'final review lens-skipped docs-comments reason=cap' \
  'final review lens security — 0 Critical, 1 Important, 2 Minor; fixed 1, rejected 1' \
  'Test ratio: 40 test / 100 code lines (abc1234..def5678)' \
  'Final review: clean (commits abc1234..def5678)')

out=$(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN" --from "$WT"); rc=$?
check "A7: --from <worktree>: exit 0 and the record's path" "$rc:$out" "0:$REVIEW"
check "A5/A6: the record holds the review lines verbatim, in ledger order" "$(cat "$REVIEW" 2>/dev/null)" "$want"

rm -f "$REVIEW"
out=$(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN"); rc=$?
check "A7/A13: no --from: the worktree ledger is found past a stale one" "$rc:$out" "0:$REVIEW"
check "A7/A13: no --from: the record comes from the worktree ledger" "$(cat "$REVIEW" 2>/dev/null)" "$want"

printf 'stale\n' > "$REVIEW"
(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN" >/dev/null)
check "A9: a rerun replaces the record" "$(cat "$REVIEW" 2>/dev/null)" "$want"
check "A9: a rerun leaves one record" "$(ls "$TOP/docs/dforge/reviews" | wc -l | tr -d ' ')" 1

printf '# Q\n' > "$TOP/docs/dforge/plans/2026-01-01-q.md"
printf '# Q\n' > "$WT/docs/dforge/plans/2026-01-01-q.md"
ledger "$WT" 2026-01-01-q "$WT/docs/dforge/plans/2026-01-01-q.md" \
  'Task 1: complete (commits abc1234..bcd2345) — discovered: none' \
  'Acceptance QA: dispatched (base abc1234)'
(cd "$TOP" && bash "$P/scripts/review-record" retain "$TOP/docs/dforge/plans/2026-01-01-q.md" >/dev/null 2>&1); rc=$?
check "A8: a ledger with no review lines: exit 3" "$rc" 3
check "A8: a ledger with no review lines: no record" "$(exists "$TOP/docs/dforge/reviews/2026-01-01-q.md")" no

printf '# R\n' > "$TOP/docs/dforge/plans/2026-01-01-r.md"
err=$(cd "$TOP" && bash "$P/scripts/review-record" retain "$TOP/docs/dforge/plans/2026-01-01-r.md" 2>&1 >/dev/null); rc=$?
check "A8: no ledger: exit 4" "$rc" 4
check "A8: no ledger: names the worktree path it searched" "$(grep -cF "$WT/.dforge/sdd/2026-01-01-r/progress.md" <<<"$err")" 1
check "A8: no ledger: no record" "$(exists "$TOP/docs/dforge/reviews/2026-01-01-r.md")" no

(cd "$TOP" && bash "$P/scripts/review-record" retain >/dev/null 2>&1); rc=$?
check "retain: no plan is a usage error" "$rc" 2

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/review-record.test.sh`
Expected: FAIL (the script does not exist); only the two "no record" checks pass, last line `2 passed, 10 failed`, exit 1.

- [ ] **Step 3: Implement**

1. Create `plugins/dforge/scripts/review-record` (mode 755) with a header comment naming the two subcommands and their exit codes, `set -uo pipefail`, `HERE` set as in `scripts/register`, and `lib/roots.sh` and `lib/plan.sh` sourced. A `usage` function prints both forms to stderr and exits 2. Dispatch on `$1`: `retain` and `ratio` (Task 2 fills `ratio`; until then it is a usage error). Any other first argument is usage.
2. `retain PLAN_FILE [--from CHECKOUT]`: exactly one plan argument, `--from` optional and taking one value; anything else is usage. Compute `slug` as the plan's basename without `.md`, `name` as `dforge_name PLAN_FILE`, and the plan's name key as `plan_ledger` computes it (`dforge_name_key` of the name).
3. Build the candidate ledger paths in order, each `"$(dforge_ledger_dir "$slug" <dir>)/progress.md"`: with `--from`, only `<dir>` = CHECKOUT; without it, the current checkout's top level first, then every worktree `git worktree list --porcelain` names (strip `\r`), dropping a path already listed, which is how the shared darkmem mirror appears once.
4. Take the first candidate that exists and whose `ledger_plan` identity, resolved with `dforge_name <named> <candidate's checkout>` and keyed with `dforge_name_key`, equals the plan's key. A ledger naming another plan is skipped. When none qualifies, print `review-record: no ledger for <name>; searched:` and then each candidate path on its own line to stderr, and exit 4.
5. From that ledger, keep the Selected ledger lines (Contracts) with `tr -d '\r'` and an anchored `grep -E`. None: print the exit-3 stderr line and exit 3, writing nothing.
6. Write `<dforge_docs_root>/reviews/<slug>.md` in the Retained file format (Contracts), `Retained:` being `date +%Y-%m-%d`: `mkdir -p` the directory, write to a temporary file beside it, then `mv` it over the target, so a rerun replaces the file whole. Print the target's path and exit 0.
7. In `scripts/test-shards.mjs`, add `'review-record.test.sh': 20,` to `windowsSeconds` in alphabetical position.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/review-record.test.sh`
Expected: `12 passed, 0 failed`, exit 0.

Run: `timeout 120 node --test tests/test-shards.test.mjs`
Expected: every test passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-record plugins/dforge/tests/review-record.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): retain a plan's review lines"
```

### Task 2: Compute the per-plan test ratio

**Files:**
- Modify: `plugins/dforge/scripts/review-record`
- Test: `plugins/dforge/tests/review-record.test.sh`

**Interfaces:**
- Consumes: the Script entry of Contracts, from Task 1
- Produces: the `ratio` and Test lens path entries of Contracts

**Items:** 2
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/review-record.test.sh`, insert this section directly above the `printf '\n%d passed, %d failed\n'` line:

```bash
# --- ratio ---
R="$TMP/ratio"
git init -q -b main "$R"
printf 'base\n' > "$R/README"
git -C "$R" add -A && git -C "$R" commit -q -m base
B=$(git -C "$R" rev-parse HEAD)
lines() { # lines <path> <count>
  mkdir -p "$(dirname "$R/$1")"
  seq "$2" | sed 's/^/line /' > "$R/$1"
}
short() { git -C "$R" rev-parse --short=7 "$1"; }

lines tests/a.test.sh 3
lines src/app.js 5
lines skills/x/SKILL.md 2
lines docs/guide.md 4
lines package-lock.json 7
lines tests/fixtures/data.txt 6
lines src/__snapshots__/a.snap 2
lines testdata/x.txt 1
lines gen/out.js 9
printf 'gen/* linguist-generated\n' > "$R/.gitattributes"
printf '\000\001\002' > "$R/bin.dat"
git -C "$R" add -A && git -C "$R" commit -q -m c1
H1=$(git -C "$R" rev-parse HEAD)
out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$B" "$H1"); rc=$?
check "A1-A4: tests, code, Markdown and .gitattributes counted; fixtures, snapshots, testdata, generated, docs, lock and binary left out" \
  "$rc:$out" "0:Test ratio: 3 test / 8 code lines ($(short "$B")..$(short "$H1"))"

git -C "$R" mv src/app.js src/main.js
echo 'line 6' >> "$R/src/main.js"
git -C "$R" commit -q -am c2
H2=$(git -C "$R" rev-parse HEAD)
out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$H1" "$H2"); rc=$?
check "A4: a rename counts only its changed lines" "$rc:$out" "0:Test ratio: 0 test / 1 code lines ($(short "$H1")..$(short "$H2"))"

lines tests/b.test.sh 2
git -C "$R" add -A && git -C "$R" commit -q -m c3
H3=$(git -C "$R" rev-parse HEAD)
out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$H2" "$H3"); rc=$?
check "A1: zero code lines still exits 0" "$rc:$out" "0:Test ratio: 2 test / 0 code lines ($(short "$H2")..$(short "$H3"))"

PLUG="$TMP/plug"
mkdir -p "$PLUG/criteria/lenses"
cp -R "$P/scripts" "$PLUG/scripts"
printf '# Test Quality Lens\n\nApplies: always\n' > "$PLUG/criteria/lenses/test-quality.md"
out=$(cd "$R" && bash "$PLUG/scripts/review-record" ratio "$B" "$H1" 2>/dev/null); rc=$?
check "A14: a lens with no paths clause: exit 2 and no line" "$rc:$out" "2:"

out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$B" no-such-rev 2>/dev/null); rc=$?
check "ratio: an unknown revision: exit 2 and no line" "$rc:$out" "2:"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/review-record.test.sh`
Expected: the 12 retain checks pass; of the 5 ratio checks the three counting checks fail and the two exit-2 checks pass on the usage error, last line `14 passed, 3 failed`, exit 1.

- [ ] **Step 3: Implement**

1. `ratio MERGE_BASE HEAD`: exactly two arguments, else usage. Each must resolve with `git rev-parse --verify --quiet <rev>^{commit}`; an unknown one prints `review-record: unknown revision <rev>` to stderr and exits 2.
2. Read the first `Applies:` line of `$HERE/../criteria/lenses/test-quality.md` (strip `\r`), split its clauses on ` ; ` as `scripts/lens-route` `lens_match` does, and take the words after `paths` of the clause whose first word is `paths`. No such clause, or no words: print `review-record: <lens path> has no paths clause` to stderr and exit 2.
3. Read `git diff --numstat -z -M <MERGE_BASE> <HEAD>` (with `-c core.quotepath=off`). A record is `<added>\t<deleted>\t<path>\0`, or for a rename `<added>\t<deleted>\t\0<old>\0<new>\0`; use the new path. `-` as the added count is a binary file and adds nothing.
4. Classify each path, first match wins (bash `case` with `set -f` around the glob loop, so `*` crosses `/`):
   - skipped: a path component equal to `fixtures`, `snapshots`, `__snapshots__` or `testdata`, or `git check-attr linguist-generated -- <path>` reporting `set` or `true` (batch the paths through one `git check-attr -z --stdin` call);
   - test: matches one of the lens's `paths` globs;
   - excluded: starts with `docs/`, or lies under `dforge_docs_root` made repository-relative when that root is inside the repository, or has a basename in the spec's lock-file list: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lock`, `bun.lockb`, `Cargo.lock`, `poetry.lock`, `uv.lock`, `Pipfile.lock`, `Gemfile.lock`, `composer.lock`, `go.sum`, `packages.lock.json`, `flake.lock`;
   - code: everything else.
5. Sum the added counts of test and code paths and print `Test ratio: <t> test / <c> code lines (<base7>..<head7>)` with `git rev-parse --short=7` of each revision. Exit 0.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/review-record.test.sh`
Expected: `17 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-record plugins/dforge/tests/review-record.test.sh
git commit -m "feat(dforge): compute the per-plan test ratio"
```

### Task 3: Write the review lines in the final review

**Files:**
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/reference/native-codex.md`
- Modify: `plugins/dforge/skills/subagent-driven-development/references/ledger.md`

**Interfaces:**
- Consumes: the `ratio` and New ledger lines entries of Contracts, from Task 2
- Produces: the ledger lines Task 1's `retain` selects

**Items:** 2, 3
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: No new test, because the change is agent-instruction prose that no script reads, carried by spec statements A10-A12 (register row 12)**

- [ ] **Step 2: Confirm the anchors**

Run:

```bash
grep -nF 'or `both`, and' plugins/dforge/reference/final-review.md
grep -n '^## Fixing what it finds' plugins/dforge/reference/final-review.md
grep -nF 'Whoever fixes writes `<workspace>/final-fix-report.md`' plugins/dforge/reference/final-review.md
grep -nF 'skipped in the report.' plugins/dforge/reference/native-codex.md
grep -n '^Final fix: implementer' plugins/dforge/skills/subagent-driven-development/references/ledger.md
```

Expected: one line from each command. The sentences below may wrap across lines in the files; match their words, not their line breaks.

- [ ] **Step 3: Implement**

1. `reference/final-review.md`, the dedupe paragraph of step 3: after the words "tags each `claude`, `codex`, or `both`, and" (they wrap after "tags each") insert "keeps each lens finding's `[lens:<id>]` tag, and", so the merged list still names each finding's lens.
2. `reference/final-review.md`, the paragraph that begins "Whoever fixes writes `<workspace>/final-fix-report.md`: what changed per": after the words "under `REJECTED: <finding>` with its evidence." insert "Each per-finding entry and each `REJECTED:` line keeps the finding's `[lens:<id>]` tag, and the scoped re-review quotes that tag in its verdict on each rejection."
3. `reference/final-review.md`: append this section at the end of the file, after `## Fixing what it finds` and its text:

   ```markdown
   ## Retained lines

   After the fix wave and its scoped re-review, or straight after step 4 when no
   fix wave ran, append these lines to the ledger, each unless the ledger already
   holds it, before the execution skill appends `Final review: clean`.
   dforge:finishing-a-development-branch copies them into the plan's review
   record, because cleanup deletes the ledger.

   - One line per lens that ran:
     `final review lens <id> — <c> Critical, <i> Important, <m> Minor; fixed <f>, rejected <r>`.
     The raised counts come from that lens report's `## Verdict`. `fixed` and
     `rejected` come from `final-fix-report.md` and `final-rereview-report.md`,
     and with two lists from the dedupe report's `REJECTED` marks, counted by
     each finding's `[lens:<id>]` tag. `rejected` counts a judge's rejection
     and a fixer's rejection the re-review upheld. A parked finding is in the
     raised counts only. A lens with no findings still gets its line.
   - `final review lenses off`, once, when `lensCap` is 0: step 1 printed
     `lenses off`, or, on a Codex host, `scripts/dforge-config get lensCap`
     prints `0`.
   - The test ratio: run
     `bash <plugin-root>/scripts/review-record ratio <MERGE_BASE> HEAD` and
     append the line it prints. On exit 2 append nothing; the review still
     ends clean.

   Name the `Test ratio:` line in the report above the finishing menu. No gate,
   route or finish decision reads these lines.
   ```

4. `reference/native-codex.md`: after the sentence ending "and name the rest as skipped in the report." (it wraps before "skipped") insert "Ledger each lens you skip as `final review lens-skipped <id> reason=cap`; with `lensCap` 0, write `final review lenses off` instead of skipped lines. Then write the lines final-review.md's Retained lines names."
5. `skills/subagent-driven-development/references/ledger.md`, the ledger format block: directly after the `Final fix: implementer <agent> (assigned; base <sha7>)` line insert:

   ```
   final review lens-skipped <id> reason=<cap|depth>
   final review lens <id> — <c> Critical, <i> Important, <m> Minor; fixed <f>, rejected <r>
   final review lenses off
   Test ratio: <t> test / <c> code lines (<base7>..<head7>)
   ```

- [ ] **Step 4: Run the checks**

Run: `timeout 1500 node scripts/test-all.mjs`
Expected: every suite passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/final-review.md plugins/dforge/reference/native-codex.md plugins/dforge/skills/subagent-driven-development/references/ledger.md
git commit -m "docs(dforge): ledger review lines in final review"
```

### Task 4: Call retain at finishing and list ratios at closing

**Files:**
- Modify: `plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md`
- Modify: `plugins/dforge/skills/closing-a-milestone/SKILL.md`
- Modify: `plugins/dforge/reference/project-state.md`

**Interfaces:**
- Consumes: the `retain` and Retained file format entries of Contracts, from Task 1
- Produces: none

**Items:** 2, 3
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: No new test, because the change is agent-instruction prose that no script reads, carried by spec statements A10-A12 (register row 12)**

- [ ] **Step 2: Confirm the anchors**

Run:

```bash
E=plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md
grep -nF 'record the plan (Step 5b), clean up the' "$E"
grep -nF 'First record the plan in the completed index (Step 5b)' "$E"
grep -n '^### Option 3: Keep As-Is' "$E"
grep -nF 'It recommends only and removes' plugins/dforge/skills/closing-a-milestone/SKILL.md
grep -n '^  registers/' plugins/dforge/reference/project-state.md
```

Expected: one line from each command. The sentences below wrap across lines in the files; match their words, not their line breaks.

- [ ] **Step 3: Implement**

1. `execute-choice.md`, Option 1: change "record the plan (Step 5b), clean up the worktree (Step 6)" to "record the plan (Step 5b) with its review record (The review record, below), clean up the worktree (Step 6)".
2. `execute-choice.md`, Option 2: change "First record the plan in the completed index (Step 5b) and commit it on the branch" to "First record the plan in the completed index (Step 5b) with its review record (The review record, below) and commit them on the branch".
3. `execute-choice.md`: insert this section directly above `### Option 3: Keep As-Is`:

   ````markdown
   ### The review record

   When the plan has a ledger, write its review record before Step 5b's commit:

   ```bash
   bash <plugin-root>/scripts/review-record retain PLAN_FILE [--from <worktree path>]
   ```

   On Option 1 from a linked worktree, pass the literal `WORKTREE_PATH` Step 2
   captured as `--from`: Step 5b runs in the main checkout, and the ledger is
   in the worktree. Option 2 runs where the ledger is and needs no `--from`.
   Add the path the script prints to the commit that holds the index line, or
   push it with the mirror, as `completed.md` is, while documents live in
   darkmem.

   - Exit 3: the ledger holds no review lines. Say so in one line and go on.
   - Exit 4: no ledger was found, and the script printed where it looked. Do
     not go on to Step 6, which deletes the workspace, until you have found
     the ledger and rerun with `--from`. When it cannot be found, tell your
     human partner that the review record will be lost before Step 6 runs;
     in an auto run, name the loss in the final message.

   Option 3 and a discard write no review record.
   ````

4. `skills/closing-a-milestone/SKILL.md`, step 8: after "It recommends only and removes nothing." add "When it recommends the cleanup, the report also lists the `Test ratio:` line of each `<docs>/reviews/*.md` file that `git diff --name-only --diff-filter=A <previous close sha7>..<milestone head> -- <docs>/reviews` names, or, while documents live in the darkmem mirror, of each whose `Retained:` date is after the previous close's commit date (`git log -1 --format=%cs <previous close sha7>`), every one when there is no previous milestone. The lines inform the reader and do not change the recommendation."
5. `reference/project-state.md`:
   - in the layout block, directly below the `registers/` line, add `  reviews/               one review record per finished plan`, aligned with its neighbours;
   - in "The files, by full path", add `- <docs>/reviews/*.md` below the registers line;
   - in "Who writes what", add the row `` | `reviews/*.md` | dforge:finishing-a-development-branch, through `scripts/review-record` | dforge:closing-a-milestone, and a person weighing review depth | `` below the registers row;
   - in "What never happens to these files", add the sentence "`reviews/*.md` is written only by `scripts/review-record`, one file per plan; nothing deletes it, and dforge:distilling-docs never touches it."

- [ ] **Step 4: Run the checks**

Run: `timeout 1500 node scripts/test-all.mjs`
Expected: every suite passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md plugins/dforge/skills/closing-a-milestone/SKILL.md plugins/dforge/reference/project-state.md
git commit -m "docs(dforge): keep review records at finishing"
```
