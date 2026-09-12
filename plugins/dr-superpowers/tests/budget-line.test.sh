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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
