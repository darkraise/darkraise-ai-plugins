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
# MSYS_NO_PATHCONV is exported below so jq --arg values stay opaque, which
# also stops Git Bash converting a POSIX TMP for native git; hand git a
# mixed-form path it understands on every host.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
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
posix() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }
check "no usage: line" "$out" "budget: unknown of 475k — unknown — no usage entry in $(posix "$T")"

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
