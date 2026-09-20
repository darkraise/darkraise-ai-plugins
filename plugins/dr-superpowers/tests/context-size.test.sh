#!/usr/bin/env bash
# context-size must measure the main session's context from its transcript —
# ignoring subagent, synthetic and interrupted entries, restarting at the last
# compaction — find the transcript by session record or, failing that, by
# guess, and print one budget line with a verdict exit code. The budget sits a
# task's growth below the compaction point of the session's model and settings.
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
unset DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR

REPO="$TMP/repo"
git init -q "$REPO"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
KEY=$(printf '%s' "$(native "$(cd "$REPO" && pwd)")" | tr -c 'A-Za-z0-9' '-')
PROJ="$HOME/.claude/projects/$KEY"
SESS="$HOME/.claude/dr-superpowers/sessions"
mkdir -p "$PROJ" "$SESS"
settings() { printf '{
  "autoCompactWindow": %s
}
' "$1" > "$HOME/.claude/settings.json"; }
settings 650000

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
check "record: line" "$out" "budget: 285k of 465k (61%) — ok — source: record"

# --- over budget ---
asst 500000 > "$T"
run
check "over: exit 5" "$status" "5"
check "over: line" "$out" "budget: 500k of 465k (107%) — handoff — source: record"

# --- boundary with no assistant after it: postTokens ---
{ asst 460000; boundary 12000; userline; } > "$T"
run
check "boundary only: line" "$out" "budget: 12k of 465k (2%) — ok — source: record"

# --- boundary then an assistant ---
{ asst 460000; boundary 12000; userline; asst 30000; } > "$T"
run
check "after boundary: line" "$out" "budget: 30k of 465k (6%) — ok — source: record"

# --- usable entry outside the 400-line tail window ---
{ asst 50000; for i in $(seq 1 450); do userline; done; } > "$T"
run
check "whole-file fallback: line" "$out" "budget: 50k of 465k (10%) — ok — source: record"

# --- no usage entry ---
userline > "$T"
run
check "no usage: exit 3" "$status" "3"
posix() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }
check "no usage: line" "$out" "budget: unknown of 465k — unknown — no usage entry in $(posix "$T")"

# --- budget override ---
asst 285000 > "$T"
DR_SUPERPOWERS_BUDGET=300000 run
check "override: line" "$out" "budget: 285k of 300k (95%) — ok — source: record"

# --- the budget follows the model's window and autoCompactWindow ---
asst 30000 false claude-haiku-4-5-20251001 > "$T"
run
check "haiku: 200k window caps the compaction point" "$out" "budget: 30k of 46k (65%) — ok — source: record"
asst 285000 false claude-sonnet-5 > "$T"
settings 2000000
run
check "window beats a larger autoCompactWindow" "$out" "budget: 285k of 790k (36%) — ok — source: record"
rm -f "$HOME/.claude/settings.json"
run
check "no settings: the model's window" "$out" "budget: 285k of 790k (36%) — ok — source: record"
settings 650000
DR_SUPERPOWERS_BUDGET=junk run
check "invalid override is ignored" "$out" "budget: 285k of 465k (61%) — ok — source: record"
run --plan docs/p.md
check "arguments: exit 2" "$status" "2"

# --- CRLF transcript ---
asst 285000 | sed 's/$/\r/' > "$T"
run
check "crlf: line" "$out" "budget: 285k of 465k (61%) — ok — source: record"

# --- record whose session is not the newest in its project directory ---
asst 285000 > "$T"
touch -d '5 minutes ago' "$T"
asst 1000 > "$PROJ/other.jsonl"
run
check "record?: line" "$out" "budget: 285k of 465k (61%) — ok — source: record?"

# --- no record: newest transcript, flagged as a guess ---
rm -f "$SESS/$KEY.json"
asst 100000 > "$PROJ/other.jsonl"
run
check "guessed: line" "$out" "budget: 100k of 465k (21%) — ok — source: guessed"
has "guessed: warns on stderr" "$(cat "$TMP/stderr")" "a guess"

# --- CLAUDE_CONFIG_DIR moves the transcripts; session records stay under HOME ---
ALT="$TMP/alt"
mkdir -p "$ALT/projects"
mv "$PROJ" "$ALT/projects/$KEY"
out=$(cd "$REPO" && CLAUDE_CONFIG_DIR="$ALT" bash "$SCRIPT" 2>"$TMP/stderr")
check "CLAUDE_CONFIG_DIR: guessed line, no settings there" "$out" "budget: 100k of 790k (12%) — ok — source: guessed"
mv "$ALT/projects/$KEY" "$PROJ"

# --- nothing to read ---
HOME="$TMP/empty" run
check "no transcript: exit 3" "$status" "3"
check "no transcript: line, no settings" "$out" "budget: unknown of 790k — unknown — no transcript found"

# --- no jq ---
DR_SUPERPOWERS_JQ=no-such-jq run
check "no jq: exit 3" "$status" "3"
check "no jq: line" "$out" "budget: unknown of 465k — unknown — no jq"

# --- usage ---
run extra
check "usage: exit 2" "$status" "2"

# --- Codex rollout measurement ---
# The context size is the last token_count event's last_token_usage.input_tokens.
# A compaction is already reflected in it, so no boundary arithmetic applies,
# and total_token_usage is a cumulative counter that must never be read.
. "$HERE/../scripts/lib/context.sh"

meta() { # meta <cwd> [originator] [source]
  # Built with jq, never printf: a native Windows cwd carries single
  # backslashes, and pasting one into a JSON string produces invalid escapes
  # (`\U`, `\A`) that jq then refuses. That would leave `.payload.cwd` empty and
  # make every discovery test pass or fail for the wrong reason.
  # MSYS_NO_PATHCONV=1 is already exported above, which keeps --arg opaque.
  ctx_jq -c -n --arg cwd "$1" --arg orig "${2:-}" --arg src "${3:-cli}" \
    '{timestamp:"2026-09-15T14:52:58.691Z",ordinal:0,type:"session_meta",
      payload:({session_id:"01a0a58e-8e6c-72b0-92a3-b1586a8ca0ec",cwd:$cwd,
                source:$src,cli_version:"0.154.0",model_provider:"openai"}
               + (if $orig == "" then {} else {originator:$orig} end))}'
}
usage_line() { # usage_line <last_input_tokens> <total_input_tokens>
  printf '{"timestamp":"2026-09-15T14:53:06.085Z","ordinal":10,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":%s,"cached_input_tokens":0,"output_tokens":7,"total_tokens":%s},"last_token_usage":{"input_tokens":%s,"cached_input_tokens":0,"output_tokens":7,"total_tokens":%s}}}}\n' \
    "$2" "$2" "$1" "$1"
}
null_usage() { printf '{"timestamp":"2026-09-15T14:53:06.085Z","ordinal":9,"type":"event_msg","payload":{"type":"token_count","info":null}}\n'; }
compacted_line() { printf '{"timestamp":"2026-09-15T14:59:00.000Z","ordinal":20,"type":"compacted","payload":{"message":"","replacement_history":[{"type":"message","role":"user"}]}}\n'; }

ROLL="$TMP/roll.jsonl"
{ meta 'C:\x'; usage_line 19545 19545; usage_line 171517 400000; } > "$ROLL"
check "rollout: measures the last last_token_usage" "$(ctx_measure_rollout "$ROLL")" "171517"

{ meta 'C:\x'; usage_line 171517 400000; null_usage; } > "$ROLL"
check "rollout: skips a null info" "$(ctx_measure_rollout "$ROLL")" "171517"

{ meta 'C:\x'; usage_line 239510 900000; compacted_line; usage_line 51326 950000; } > "$ROLL"
check "rollout: takes the post-compaction reading" "$(ctx_measure_rollout "$ROLL")" "51326"

{ meta 'C:\x'; printf 'not json\n'; } > "$ROLL"
ctx_measure_rollout "$ROLL" >/dev/null 2>&1
check "rollout: a file with no usage returns 1" "$?" "1"

# The tail is read first because rollouts reach tens of megabytes; the
# whole-file fallback is what finds a reading that sits above it.
{ meta 'C:\x'; usage_line 88000 99000; } > "$ROLL"
i=0; while [ "$i" -lt 500 ]; do compacted_line >> "$ROLL"; i=$((i + 1)); done
check "rollout: falls back past a 400-line tail" "$(ctx_measure_rollout "$ROLL")" "88000"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
