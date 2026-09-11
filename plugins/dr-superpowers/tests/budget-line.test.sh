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
