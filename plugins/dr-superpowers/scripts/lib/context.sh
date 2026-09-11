# Measure the running Claude session's context against the handoff budget.
# Sourced by scripts/context-size; defines functions only.
#
# The transcript schema is observed, not documented: main-chain entries carry
# isSidechain false, assistant entries carry message.usage, and compaction
# writes a system entry with subtype compact_boundary. A schema change must
# degrade the verdict to unknown, never produce a wrong number.

CTX_DEFAULT_BUDGET=475000

ctx_jq() { "${DR_SUPERPOWERS_JQ:-jq}" "$@"; }
ctx_have_jq() { command -v "${DR_SUPERPOWERS_JQ:-jq}" >/dev/null 2>&1; }

# Keys are built from the native path so they match what the hook received from
# Claude Code (a Windows path under Git Bash).
ctx_native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}
ctx_posix() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}
ctx_key() { printf '%s' "$(ctx_native "$1")" | tr -c 'A-Za-z0-9' '-'; }

ctx_candidates() {
  printf '%s\n' "$PWD"
  local root common
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  printf '%s\n' "$root"
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || true
}

# Sets CTX_TRANSCRIPT and CTX_SOURCE (record | record? | guessed); returns 1
# when no transcript is found. Records go first across every candidate, so a
# worktree's own old transcript never outranks the running session's record.
ctx_find_transcript() {
  CTX_TRANSCRIPT="" CTX_SOURCE=""
  local cands c key rec tp sid newest
  cands=$(ctx_candidates)
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    key=$(ctx_key "$c")
    rec="$HOME/.claude/dr-superpowers/sessions/$key.json"
    [ -f "$rec" ] || continue
    # Read the record on stdin: a native jq cannot open a POSIX path when MSYS
    # path conversion is off.
    tp=$(ctx_jq -r '.transcript_path // empty' <"$rec" 2>/dev/null | tr -d '\r')
    [ -n "$tp" ] || continue
    tp=$(ctx_posix "$tp")
    [ -f "$tp" ] || continue
    CTX_TRANSCRIPT=$tp CTX_SOURCE=record
    sid=$(ctx_jq -r '.session_id // empty' <"$rec" 2>/dev/null | tr -d '\r')
    newest=$(ls -t "$HOME/.claude/projects/$key"/*.jsonl 2>/dev/null | head -n 1)
    if [ -n "$newest" ] && [ -n "$sid" ] && [ "$(basename "$newest" .jsonl)" != "$sid" ]; then
      CTX_SOURCE='record?'
    fi
    return 0
  done <<<"$cands"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    newest=$(ls -t "$HOME/.claude/projects/$(ctx_key "$c")"/*.jsonl 2>/dev/null | head -n 1)
    if [ -n "$newest" ]; then CTX_TRANSCRIPT=$newest CTX_SOURCE=guessed; return 0; fi
  done <<<"$cands"
  return 1
}

# stdin: transcript lines. stdout: token count, or nothing.
ctx_reduce() {
  tr -d '\r' | ctx_jq -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select((.isSidechain // false) == false)
     | if .type == "system" and .subtype == "compact_boundary" then {b: .compactMetadata.postTokens}
       elif .type == "assistant" and (.message.model // "") != "<synthetic>"
            and ((.message.usage | type) == "object") then
         ((.message.usage.input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)
          + (.message.usage.cache_read_input_tokens // 0)) as $t
         | if $t > 0 then {a: $t} else empty end
       else empty end]
    | reduce .[] as $e ({}; if ($e | has("b")) then {b: $e.b} else . + {a: $e.a} end)
    | (.a // .b) // empty' 2>/dev/null
}

# ctx_measure FILE — the last main-chain assistant usage after the last
# compaction boundary, else that boundary's postTokens. Reads the tail first:
# transcripts reach tens of megabytes.
ctx_measure() {
  local out
  out=$(tail -n 400 "$1" | ctx_reduce)
  [ -n "$out" ] || out=$(ctx_reduce < "$1")
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# Print the budget line; return 0 ok, 5 handoff, 3 unknown.
ctx_line() {
  local budget=${DR_SUPERPOWERS_BUDGET:-$CTX_DEFAULT_BUDGET} tokens bk tk pct
  case $budget in ''|*[!0-9]*) budget=$CTX_DEFAULT_BUDGET ;; esac
  [ "$budget" -gt 0 ] || budget=$CTX_DEFAULT_BUDGET
  bk=$(( (budget + 500) / 1000 ))
  if ! ctx_have_jq; then echo "budget: unknown of ${bk}k — unknown — no jq"; return 3; fi
  if ! ctx_find_transcript; then echo "budget: unknown of ${bk}k — unknown — no transcript found"; return 3; fi
  if ! tokens=$(ctx_measure "$CTX_TRANSCRIPT"); then
    echo "budget: unknown of ${bk}k — unknown — no usage entry in $CTX_TRANSCRIPT"; return 3
  fi
  tk=$(( (tokens + 500) / 1000 ))
  pct=$(( tokens * 100 / budget ))
  if [ "$tokens" -ge "$budget" ]; then
    echo "budget: ${tk}k of ${bk}k (${pct}%) — handoff — source: $CTX_SOURCE"
    return 5
  fi
  echo "budget: ${tk}k of ${bk}k (${pct}%) — ok — source: $CTX_SOURCE"
}
