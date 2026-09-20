# Measure the running Claude session's context against the handoff budget.
# Sourced by scripts/context-size; defines functions only.
#
# The transcript schema is observed, not documented: main-chain entries carry
# isSidechain false, assistant entries carry message.usage, and compaction
# writes a system entry with subtype compact_boundary. A schema change must
# degrade the verdict to unknown, never produce a wrong number.

# Auto-compaction fires at about 93% of the effective window; the budget sits
# one worst-case task's growth below that, so a task in flight always lands.
CTX_COMPACT_PCT=93
CTX_TASK_MARGIN=140000

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
    newest=$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$key"/*.jsonl 2>/dev/null | head -n 1)
    if [ -n "$newest" ] && [ -n "$sid" ] && [ "$(basename "$newest" .jsonl)" != "$sid" ]; then
      CTX_SOURCE='record?'
    fi
    return 0
  done <<<"$cands"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    newest=$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(ctx_key "$c")"/*.jsonl 2>/dev/null | head -n 1)
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

# ctx_model FILE — the model of the last main-chain assistant entry, or nothing.
ctx_model_reduce() {
  tr -d '\r' | ctx_jq -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select((.isSidechain // false) == false and .type == "assistant")
     | .message.model // empty | select(. != "<synthetic>")] | last // empty' 2>/dev/null
}
ctx_model() {
  local out
  out=$(tail -n 400 "$1" | ctx_model_reduce)
  [ -n "$out" ] || out=$(ctx_model_reduce < "$1")
  printf '%s' "$out"
}

ctx_model_window() {
  case $1 in
    *haiku*) echo 200000 ;;
    *) echo 1000000 ;;
  esac
}

# Codex rollout entries are one JSON object per line. The context size is the
# last token_count event's last_token_usage.input_tokens: it already reflects a
# compaction, so nothing here reads the compacted record, and total_token_usage
# is a cumulative counter (28 million in one observed session) that would read
# as a context size if taken by mistake. An entry whose info is null carries no
# usage and is skipped.
ctx_rollout_reduce() {
  tr -d '\r' | ctx_jq -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select(.type == "event_msg")
     | .payload | objects | select(.type == "token_count")
     | .info | objects
     | .last_token_usage | objects
     | .input_tokens | numbers]
    | last // empty' 2>/dev/null
}

# ctx_measure_rollout FILE — the context size, or nothing. Reads the tail first:
# rollouts reach tens of megabytes and one compacted entry embeds a whole
# replacement_history.
ctx_measure_rollout() {
  local out
  out=$(tail -n 400 "$1" | ctx_rollout_reduce)
  [ -n "$out" ] || out=$(ctx_rollout_reduce < "$1")
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# A session being written to is among the very newest files, and the sessions
# tree holds years of history: an unbounded walk did not finish in 120 seconds
# on the machine this was measured on.
CTX_ROLLOUT_SCAN=40

# ctx_rollout_files DIR — rollout paths newest-first. Day directories are
# walked newest-first, then files by modification time inside each, so the
# <YYYY>/<MM>/<DD> layout does the coarse ordering without stat-ing the tree.
ctx_rollout_files() {
  local day
  find "$1" -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sort -r | while IFS= read -r day; do
    ls -t "$day"/rollout-*.jsonl 2>/dev/null
  done
}

# Sets CTX_ROLLOUT to this session's rollout; returns 1 when none matches.
# Only interactive rollouts count. This plugin makes a Claude controller run
# Codex tasks in its own worktree through run-codex-task.sh, and those runs
# write rollouts carrying the controller's cwd; selecting one would replace a
# live Claude session's verdict with an unknown.
ctx_find_rollout() {
  CTX_ROLLOUT=""
  local sessions cands f cwd n=0
  ctx_have_jq || return 1
  sessions="${CODEX_HOME:-$HOME/.codex}/sessions"
  [ -d "$sessions" ] || return 1
  # ctx_native emits its own newline under Git Bash and none without cygpath,
  # so the printf keeps one candidate per line on both. A blank line never
  # matches a non-empty cwd under grep -qxF.
  cands=$(ctx_candidates | while IFS= read -r c; do
    [ -n "$c" ] && ctx_native "$c" && printf '\n'
  done)
  # One jq per file, with the origin filter inside it: task-brief prints the
  # budget line before every task, so this walk is on the hot path and a
  # process spawn per field would be three times the cost on Windows.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    [ "$n" -le "$CTX_ROLLOUT_SCAN" ] || return 1
    cwd=$(head -n 1 "$f" 2>/dev/null | tr -d '\r' | ctx_jq -r '
      .payload
      | select((.originator // "") != "codex_exec" and (.source // "") != "exec")
      | .cwd // empty' 2>/dev/null)
    [ -n "$cwd" ] || continue
    if grep -qxF -- "$cwd" <<<"$cands"; then CTX_ROLLOUT=$f; return 0; fi
  done < <(ctx_rollout_files "$sessions")
  return 1
}

# autoCompactWindow from the user settings, or nothing. Read without jq so the
# budget stays printable when jq is missing.
ctx_auto_compact_window() {
  local f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  [ -f "$f" ] || return 0
  tr -d '\r' <"$f" | grep -oE '"autoCompactWindow"[[:space:]]*:[[:space:]]*[0-9]+' \
    | head -n 1 | grep -oE '[0-9]+$' || true
}

# ctx_budget MODEL — the handoff budget for a session on MODEL (may be empty).
ctx_budget() {
  local window acw point
  window=$(ctx_model_window "$1")
  acw=$(ctx_auto_compact_window)
  point=$window
  if [ -n "$acw" ] && [ "$acw" -gt 0 ] && [ "$acw" -lt "$window" ]; then point=$acw; fi
  echo $(( point * CTX_COMPACT_PCT / 100 - CTX_TASK_MARGIN ))
}

# Filled in by the observation log; a no-op until then.
ctx_log_observation() { :; }

# Print the budget line; return 0 ok, 5 handoff, 3 unknown.
ctx_line() {
  local budget="" model="" tokens bk tk pct found=0 claude="" rollout=""
  if ctx_have_jq; then
    if ctx_find_transcript; then claude=$CTX_TRANSCRIPT; fi
    if ctx_find_rollout; then rollout=$CTX_ROLLOUT; fi
  fi
  # The live session is the one still being appended to. Session records are
  # never deleted, so a record source does not by itself prove a live Claude
  # session and modification time is the right tiebreak.
  if [ -n "$rollout" ] && { [ -z "$claude" ] || [ "$rollout" -nt "$claude" ]; }; then
    CTX_TRANSCRIPT=$rollout CTX_SOURCE=rollout
    if ! tokens=$(ctx_measure_rollout "$rollout"); then
      echo "budget: unknown — unknown — no usage entry in $rollout"
      return 3
    fi
    ctx_log_observation "$tokens"
    tk=$(( (tokens + 500) / 1000 ))
    # No denominator: no Codex budget has been set yet, and the verdict stays
    # unknown so reference/session-budget.md's count rule keeps the session.
    # DR_SUPERPOWERS_BUDGET stays a Claude override for the same reason.
    echo "budget: ${tk}k measured — unknown — source: rollout"
    return 3
  fi
  if [ -n "$claude" ]; then
    found=1
    CTX_TRANSCRIPT=$claude
    model=$(ctx_model "$CTX_TRANSCRIPT")
  fi
  case ${DR_SUPERPOWERS_BUDGET:-} in
    ''|*[!0-9]*) ;;
    *) [ "$DR_SUPERPOWERS_BUDGET" -gt 0 ] && budget=$DR_SUPERPOWERS_BUDGET ;;
  esac
  [ -n "$budget" ] || budget=$(ctx_budget "$model")
  bk=$(( (budget + 500) / 1000 ))
  if ! ctx_have_jq; then echo "budget: unknown of ${bk}k — unknown — no jq"; return 3; fi
  if [ "$found" -eq 0 ]; then echo "budget: unknown of ${bk}k — unknown — no transcript found"; return 3; fi
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
