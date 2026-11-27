# Measure the running Claude session's context against the handoff budget.
# Sourced by scripts/context-size; defines functions only.
#
# The transcript schema is observed, not documented: main-chain entries carry
# isSidechain false, assistant entries carry message.usage, and compaction
# writes a system entry with subtype compact_boundary. A schema change must
# degrade the verdict to unknown, never produce a wrong number.

. "$(dirname "${BASH_SOURCE[0]}")/dforge-dir.sh"

# Auto-compaction fires at about 93% of the effective window; the budget sits
# one worst-case task's growth below that, so a task in flight always lands.
# In relaxed handoff mode the final phase (final review, its fix wave,
# finishing) and a plan's last tasks get their own, higher limit; in strict
# mode they keep the task budget and run past it to finish the plan.
CTX_COMPACT_PCT=93
CTX_TASK_MARGIN=140000
CTX_FINAL_PCT=85
# A plan's last tasks join the final phase: once this many or fewer remain, they
# hand off only at hard (ctx_hard) in strict mode. Finishing them here costs
# less than a fresh session's baseline plus its reload.
CTX_TAIL_TASKS=2
# After a committed spec in relaxed mode, the plan is written in the same
# session while the context is under 150% of the task budget, capped at the
# final-phase limit so plan writing never starts at the compaction point.
# Strict mode measures against hard instead.
CTX_PLAN_PCT=150

. "$(dirname "${BASH_SOURCE[0]}")/dforge-env.sh"
. "$(dirname "${BASH_SOURCE[0]}")/auto-run.sh"
. "$(dirname "${BASH_SOURCE[0]}")/session-state.sh"

ctx_jq() { "${DFORGE_JQ:-jq}" "$@"; }
ctx_have_jq() { command -v "${DFORGE_JQ:-jq}" >/dev/null 2>&1; }

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
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  printf '%s\n' "$root"
  plan_primary_root || true
}

# Sets CTX_TRANSCRIPT and CTX_SOURCE (record | record? | guessed); returns 1
# when no transcript is found. With CLAUDE_CODE_SESSION_ID the session's own
# transcript is the only answer: two sessions in one checkout share the cwd
# record, and entering a worktree moves the transcript away from the path its
# record holds, so any other record would measure another session. Without it
# the cwd records go first across every candidate, so a worktree's own old
# transcript never outranks the running session's record.
ctx_find_transcript() {
  CTX_TRANSCRIPT="" CTX_SOURCE=""
  local cands c key rec tp sid newest own="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -n "$own" ]; then
    CTX_TRANSCRIPT=$(ar_transcript "$own") || { CTX_TRANSCRIPT=""; return 1; }
    CTX_SOURCE=record
    return 0
  fi
  cands=$(ctx_candidates)
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    key=$(ctx_key "$c")
    rec="$HOME/.claude/dforge/sessions/$key.json"
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

# ctx_count VALUE — VALUE, once a positive integer, else status 1. Callers do
# arithmetic on it, and bash arithmetic on a string runs any $(...) inside it.
ctx_count() {
  local v=${1//$'\r'/}
  [[ $v =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$v"
}

# stdin: transcript lines. stdout: token count, or nothing.
ctx_reduce() {
  tr -d '\r' | ctx_jq -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select((.isSidechain // false) == false)
     | if .type == "system" and .subtype == "compact_boundary"
       then {b: (.compactMetadata.postTokens | if type == "number" and . == floor and . > 0 then . else null end)}
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
  ctx_count "$out"
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

# ctx_window_sid — the session whose window is read: CLAUDE_CODE_SESSION_ID,
# else the transcript's name.
ctx_window_sid() {
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then printf '%s' "$CLAUDE_CODE_SESSION_ID"
  elif [ -n "${CTX_TRANSCRIPT:-}" ]; then basename "$CTX_TRANSCRIPT" .jsonl
  fi
}

# _ctx_window_lookup MODEL SID — sets CTX_WINDOW_FOUND and CTX_WINDOW_SOURCE
# (session file | table), both empty when neither knows the window. A guessed
# window would put the budget anywhere, so an unlisted model has none.
_ctx_window_lookup() {
  local w=""
  CTX_WINDOW_SOURCE=""
  if [ -n "$2" ] && ctx_have_jq && w=$(ss_window "$2"); then
    CTX_WINDOW_SOURCE="session file"
  else
    case $1 in
      *haiku*) w=200000 ;;
      claude-fable-5-* | claude-opus-5-* | claude-sonnet-5-*) w=1000000 ;;
      *) w="" ;;
    esac
    [ -z "$w" ] || CTX_WINDOW_SOURCE=table
  fi
  CTX_WINDOW_FOUND=$w
}

# ctx_window_prime MODEL — look the window up once in the caller's shell: the
# budget helpers run in subshells, and each lookup reads the session file.
ctx_window_prime() {
  local sid
  sid=$(ctx_window_sid)
  _ctx_window_lookup "$1" "$sid"
  CTX_WINDOW_CACHE_KEY="$1|$sid" CTX_WINDOW_CACHE_SOURCE=$CTX_WINDOW_SOURCE CTX_WINDOW_CACHE_VALUE=$CTX_WINDOW_FOUND
}

# ctx_model_window MODEL [SID] — the model's window in tokens; nothing and
# status 1 when it is unknown.
ctx_model_window() {
  local sid
  if [ $# -ge 2 ]; then sid=$2; else sid=$(ctx_window_sid); fi
  if [ "${CTX_WINDOW_CACHE_KEY-}" = "$1|$sid" ]; then
    CTX_WINDOW_SOURCE=$CTX_WINDOW_CACHE_SOURCE CTX_WINDOW_FOUND=$CTX_WINDOW_CACHE_VALUE
  else
    _ctx_window_lookup "$1" "$sid"
  fi
  [ -n "$CTX_WINDOW_FOUND" ] || return 1
  echo "$CTX_WINDOW_FOUND"
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
  ctx_count "$out"
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
# Codex tasks and reviews in its own worktrees, and those runs write rollouts
# carrying the controller's cwd; selecting one would replace a live Claude
# session's verdict with an unknown. `codex exec` tags its rollouts
# codex_exec/exec, and the codex plugin's app-server tags them "Claude Code".
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
      | select((.originator // "") as $o | $o != "codex_exec" and $o != "Claude Code"
          and (.source // "") != "exec")
      | .cwd // empty' 2>/dev/null)
    [ -n "$cwd" ] || continue
    if grep -qxF -- "$cwd" <<<"$cands"; then CTX_ROLLOUT=$f; return 0; fi
  done < <(ctx_rollout_files "$sessions")
  return 1
}

# autoCompactWindow from the user, then project, then local settings, the last
# file that sets it winning as in Claude Code's own merge; or nothing. Project
# settings are read only when Claude Code names the project directory. Only the
# top-level key counts: a file can carry per-model ones under modelSettings.
# Without jq the first key in the file is read, so the budget stays printable.
ctx_auto_compact_window() {
  local f v acw=""
  for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" \
           ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR/.claude/settings.json" "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"}; do
    [ -f "$f" ] || continue
    if ctx_have_jq; then
      v=$(ctx_jq -r '.autoCompactWindow | numbers | floor' <"$f" 2>/dev/null | tr -d '\r' || true)
    else
      v=$(tr -d '\r' <"$f" | grep -oE '"autoCompactWindow"[[:space:]]*:[[:space:]]*[0-9]+' \
        | head -n 1 | grep -oE '[0-9]+$' || true)
    fi
    [ -z "$v" ] || acw=$v
  done
  printf '%s' "$acw"
}

# ctx_window MODEL — the window compaction is measured against: the model's
# window, or autoCompactWindow when that is smaller; nothing and status 1 when
# the model's window is unknown.
ctx_window() {
  local window acw
  window=$(ctx_model_window "$1") || return 1
  acw=$(ctx_auto_compact_window)
  if [ -n "$acw" ] && [ "$acw" -gt 0 ] && [ "$acw" -lt "$window" ]; then window=$acw; fi
  echo "$window"
}

# ctx_budget MODEL — the handoff budget for a session on MODEL (may be empty).
# A window small enough to put the rule near or below zero holds a fifth of it.
ctx_budget() {
  local window budget
  window=$(ctx_window "$1") || return 1
  budget=$(( window * CTX_COMPACT_PCT / 100 - CTX_TASK_MARGIN ))
  [ "$budget" -ge $(( window / 5 )) ] || budget=$(( window / 5 ))
  echo "$budget"
}

# ctx_final_budget MODEL — the final phase's limit. DFORGE_BUDGET pins
# the task budget only, so it never moves this one.
ctx_final_budget() {
  local window
  window=$(ctx_window "$1") || return 1
  echo $(( window * CTX_FINAL_PCT / 100 ))
}

# ctx_pinned_budget — the task budget someone pinned: DFORGE_BUDGET, else the
# handoffTokens setting; empty when neither names a positive number. The
# environment is read here, not through the setting, so a machine without Node
# keeps its override.
ctx_pinned_budget() {
  local pinned
  case ${DFORGE_BUDGET:-} in
    ''|*[!0-9]*) pinned="" ;;
    *) pinned=$DFORGE_BUDGET; [ "$pinned" -gt 0 ] || pinned="" ;;
  esac
  if [ -z "$pinned" ]; then
    pinned=$(dforge_setting handoffTokens 0)
    case $pinned in ''|*[!0-9]*|0) pinned="" ;; esac
  fi
  printf '%s' "$pinned"
}

# ctx_plan_mode PLAN_SRC LEDGER — the context-size arguments for a check made
# while a plan runs: --final once every task has a complete line, --tail R
# while R tasks of CTX_TAIL_TASKS or fewer remain, nothing before that. Needs
# lib/plan.sh.
ctx_plan_mode() {
  local done_tasks="" counts total remaining
  [ ! -f "$2" ] || done_tasks=$(ledger_done "$2" || true)
  counts=$(plan_tasks "$1" | cut -f1 | DONE="$done_tasks" awk '
    BEGIN { n = split(ENVIRON["DONE"], d, "\n"); for (i = 1; i <= n; i++) done[d[i]] = 1 }
    !seen[$1]++ { t++; if (!($1 in done)) r++ } END { print t + 0, r + 0 }')
  read -r total remaining <<<"$counts"
  [ "$total" -gt 0 ] || return 0
  if [ "$remaining" -eq 0 ]; then
    echo --final
  elif [ "$remaining" -le "$CTX_TAIL_TASKS" ]; then
    echo "--tail $remaining"
  fi
}

# ctx_plan_budget MODEL — the limit for writing the plan after the spec:
# CTX_PLAN_PCT of the task budget (DFORGE_BUDGET included), never above
# the final-phase limit.
ctx_plan_budget() {
  local task final plan
  final=$(ctx_final_budget "$1") || return 1
  task=$(ctx_pinned_budget)
  [ -n "$task" ] || task=$(ctx_budget "$1")
  plan=$(( task * CTX_PLAN_PCT / 100 ))
  [ "$plan" -le "$final" ] || plan=$final
  echo "$plan"
}

# ctx_hard MODEL — hard (ar_hard) of the task budget, pinned or computed, and
# the window: the most a strict session holds to finish a plan's tail, its
# final phase, the plan after a spec, or the branch. Nothing and status 1 when
# the window is unknown.
ctx_hard() {
  local window budget
  window=$(ctx_window "$1") || return 1
  budget=$(ctx_pinned_budget)
  [ -n "$budget" ] || budget=$(ctx_budget "$1") || return 1
  ar_hard "$budget" "$window"
}

# The primary checkout's root: a worktree's .dforge/ lives with the checkout
# that owns the repository, so every session logs to one file.
ctx_primary_root() { plan_primary_root; }

# ctx_log_observation TOKENS — append one row, and never fail the caller: the
# budget line is printed whether or not the observation is recorded.
#
# The log lives inside .dforge/sdd/ because that directory self-ignores
# (scripts/sdd-workspace writes * into its .gitignore). Only this repository's
# root .gitignore lists the state
# directory, and an untracked-but-not-ignored file
# would enter scripts/lib/worktree-snapshot.sh's review snapshot, invalidating a
# review.
ctx_log_observation() {
  local primary base sid
  primary=$(ctx_primary_root) || return 0
  base="$(dforge_dir state "$primary")/sdd"
  mkdir -p "$base" 2>/dev/null || return 0
  dforge_self_ignore "$base"
  # A Claude row carries the window's session, so its briefs pair by session.
  if [ "${CTX_SOURCE:-}" = rollout ]; then
    sid=$(head -n 1 "${CTX_ROLLOUT:-}" 2>/dev/null | tr -d '\r' \
      | ctx_jq -r '.payload.session_id // empty' 2>/dev/null)
  else
    sid=$(ctx_window_sid)
  fi
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${DFORGE_BUDGET_CALLER:-direct}" "$sid" \
    >> "$base/budget-log.tsv" 2>/dev/null || return 0
}

# ctx_source_text — the line's source: the transcript's, and the window's when
# the cockpit's session file gave it.
ctx_source_text() {
  if [ "${CTX_WINDOW_SOURCE:-}" = "session file" ]; then printf '%s, window session file' "$CTX_SOURCE"
  else printf '%s' "$CTX_SOURCE"; fi
}

ctx_auto_label() { # ctx_auto_label REGIME
  if [ "$1" = high ]; then printf 'budget (auto, high)'; else printf 'budget (auto)'; fi
}

# ctx_auto_line TOKENS MODEL — the budget line while an auto run is bound
# to this session (reference/auto-run.md): the run's rule replaces the task
# budget, the tail, the final-phase limit and relaxed mode. Returns 0 ok,
# 6 compact, 5 handoff, 3 when the run cannot be read or the model's window
# is unknown. The run's rule needs the window (the high regime and the
# after-compaction rule measure against it), so a pinned budget does not stand
# in for an unknown one.
ctx_auto_line() {
  local tokens=$1 task=0 window out verdict limit regime label early=0
  if window=$(ctx_window "$2"); then
    task=$(ctx_pinned_budget)
    [ -n "$task" ] || task=$(ctx_budget "$2")
  else
    window=0
  fi
  case ${DFORGE_BUDGET_CALLER:-} in task-close:* | task-brief:*) early=1 ;; esac
  if ! out=$(ar_verdict "$tokens" "$task" "$window" "$early"); then
    if [ "${out%% *}" = unknown ]; then
      read -r _ _ regime <<<"$out"
      echo "$(ctx_auto_label "$regime"): $(( (tokens + 500) / 1000 ))k measured — unknown — the model's window is unknown"
    else
      echo "budget (auto): unknown — unknown — the run's state could not be updated"
    fi
    return 3
  fi
  read -r verdict limit regime <<<"$out"
  label=$(ctx_auto_label "$regime")
  echo "$label: $(( (tokens + 500) / 1000 ))k of $(( (limit + 500) / 1000 ))k ($(( tokens * 100 / limit ))%) — $verdict — source: $(ctx_source_text)"
  case $verdict in
    compact) return 6 ;;
    handoff) return 5 ;;
  esac
  return 0
}

# ctx_line [final | tail R | plan | finish] — print the budget line; return 0
# ok, 5 handoff, 6 compact (an auto run only), 3 unknown. With final, the plan's
# final phase: measured against the task budget, it hands off only at hard
# (ctx_hard). tail R does the same before one of a plan's last R tasks
# (CTX_TAIL_TASKS), so the plan finishes in this session past its budget. plan,
# the check after a committed spec, and finish, the check before finishing the
# branch, measure against hard itself. With the handoffMode setting at
# relaxed final and tail measure against the final-phase limit instead, and a
# tail task past it hands off; plan keeps ctx_plan_budget; finish measures
# against the final-phase limit and never hands off. With the handoffMode setting at relaxed, a plain task
# measures against the final-phase limit too, and the label says so. An auto run bound to the session (AR_SESSION, else
# CLAUDE_CODE_SESSION_ID) replaces every limit but the plan's with its own
# (ar_verdict, reference/auto-run.md): 6 asks for a compaction and 5 for a
# handoff. With final it first moves the run to its final phase once the
# ledger has every task complete (ar_enter_final).
ctx_line() {
  local budget="" model="" tokens bk tk pct found=0 claude="" rollout="" of window
  local label=budget
  local limit=task auto=0 regime mode finishing=0 hard="" past=0
  CTX_TOKENS=""
  mode=$(dforge_setting handoffMode strict)
  if [ "${1:-}" = final ]; then
    label="budget (final)" finishing=1
    [ "$mode" != relaxed ] || limit=final
  fi
  if [ "${1:-}" = tail ]; then
    if [ "$mode" = relaxed ]; then limit=final; else finishing=1; fi
    if [ "${2:-1}" = 1 ]; then label="budget (last task)"; else label="budget (last ${2} tasks)"; fi
  fi
  [ "${1:-}" = plan ] && label="budget (plan)" limit=plan
  if [ "${1:-}" = finish ]; then
    label="budget (finishing)"
    if [ "$mode" = relaxed ]; then limit=final finishing=1; else limit=hard; fi
  fi
  # An auto run bound to this session replaces every limit but the plan's.
  if [ "${1:-}" != plan ]; then
    AR_SESSION=${AR_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}
    if ar_bound; then
      auto=1
      # The check after the last task's complete line starts the final phase.
      [ "${1:-}" != final ] || ar_enter_final || true
      label=$(ctx_auto_label normal)
    fi
  fi
  if [ "$limit" = task ] && [ "$mode" = relaxed ]; then
    limit=relaxed
    label="budget (relaxed)"
  fi
  if ctx_have_jq; then
    if ctx_find_transcript; then claude=$CTX_TRANSCRIPT; fi
    # A session id whose own record was found names the caller: a Codex
    # session in the same checkout must not take its budget line.
    if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ] || [ "$CTX_SOURCE" != record ]; then
      if ctx_find_rollout; then rollout=$CTX_ROLLOUT; fi
    fi
  fi
  # The live session is the one still being appended to. Session records are
  # never deleted, so a record source does not by itself prove a live Claude
  # session and modification time is the right tiebreak.
  if [ -n "$rollout" ] && { [ -z "$claude" ] || [ "$rollout" -nt "$claude" ]; }; then
    CTX_TRANSCRIPT=$rollout CTX_SOURCE=rollout
    if ! tokens=$(ctx_measure_rollout "$rollout"); then
      echo "$label: unknown — unknown — no usage entry in $rollout"
      return 3
    fi
    export CTX_TOKENS=$tokens
    ctx_log_observation "$tokens"
    tk=$(( (tokens + 500) / 1000 ))
    # No denominator: no Codex budget has been set yet, and the verdict stays
    # unknown so reference/session-budget.md's count rule keeps the session.
    # DFORGE_BUDGET stays a Claude override for the same reason.
    echo "$label: ${tk}k measured — unknown — source: rollout"
    return 3
  fi
  if [ -n "$claude" ]; then
    found=1
    CTX_TRANSCRIPT=$claude
    model=$(ctx_model "$CTX_TRANSCRIPT")
  fi
  ctx_window_prime "$model"
  # An unknown window leaves the budget empty: only a pinned task budget
  # stands without one.
  [ "$mode" = relaxed ] || hard=$(ctx_hard "$model") || hard=""
  if [ "$limit" = final ] || [ "$limit" = relaxed ]; then
    budget=$(ctx_final_budget "$model") || budget=""
  elif [ "$limit" = hard ] || { [ "$limit" = plan ] && [ -n "$hard" ]; }; then
    budget=$hard
  elif [ "$limit" = plan ]; then
    budget=$(ctx_plan_budget "$model") || budget=""
  else
    budget=$(ctx_pinned_budget)
    [ -n "$budget" ] || budget=$(ctx_budget "$model") || budget=""
  fi
  # A size that cannot be read still names the run's own limit.
  if [ "$auto" = 1 ]; then
    regime=$(ar_get regime)
    regime=${regime:-normal}
    label=$(ctx_auto_label "$regime")
    budget=""
    if window=$(ctx_window "$model"); then
      budget=$(ctx_pinned_budget)
      [ -n "$budget" ] || budget=$(ctx_budget "$model")
      budget=$(ar_limit "$budget" "$window" "$regime")
    fi
  fi
  of=""
  [ -z "$budget" ] || of=" of $(( (budget + 500) / 1000 ))k"
  if ! ctx_have_jq; then echo "$label: unknown$of — unknown — no jq"; return 3; fi
  if [ "$found" -eq 0 ]; then echo "$label: unknown$of — unknown — no transcript found"; return 3; fi
  if ! tokens=$(ctx_measure "$CTX_TRANSCRIPT"); then
    echo "$label: unknown$of — unknown — no usage entry in $CTX_TRANSCRIPT"; return 3
  fi
  export CTX_TOKENS=$tokens
  ctx_log_observation "$tokens"
  if [ "$auto" = 1 ]; then
    ctx_auto_line "$tokens" "$model"
    return
  fi
  tk=$(( (tokens + 500) / 1000 ))
  if [ -z "$budget" ]; then
    echo "$label: ${tk}k measured — unknown — the model's window is unknown"
    return 3
  fi
  bk=$(( (budget + 500) / 1000 ))
  pct=$(( tokens * 100 / budget ))
  # In strict mode a plan's tail and its final phase run past the task budget
  # and hand off only at hard (reference/session-budget.md §Stops); relaxed
  # mode's final phase and finishing never hand off. An unknown hard hands
  # nothing off.
  if [ "$finishing" -eq 1 ]; then
    [ -z "$hard" ] || [ "$tokens" -lt "$hard" ] || past=1
  elif [ "$tokens" -ge "$budget" ]; then
    past=1
  fi
  if [ "$past" -eq 1 ]; then
    echo "$label: ${tk}k of ${bk}k (${pct}%) — handoff — source: $(ctx_source_text)"
    return 5
  fi
  echo "$label: ${tk}k of ${bk}k (${pct}%) — ok — source: $(ctx_source_text)"
}

# Pair consecutive task-brief rows within one session: task-brief runs once per
# task, so the growth between two briefs is one task's cost. A negative delta
# means a compaction fell between them; it is reported, never averaged into the
# data, because compaction is what the budget will be calibrated against.
ctx_observations() {
  local primary log
  primary=$(ctx_primary_root) || return 0
  log="$(dforge_dir state "$primary")/sdd/budget-log.tsv"
  [ -f "$log" ] || return 0
  tr -d '\r' < "$log" | sort -s -t $'\t' -k4,4 -k1,1 | awk -F'\t' '
    $3 ~ /^task-brief:[0-9]+$/ && $4 != "" {
      n = substr($3, 12)
      if ($4 == sid) {
        d = $2 - prev
        if (d < 0) printf "%s  Task %s -> Task %s  compacted\n", $4, pn, n
        else printf "%s  Task %s -> Task %s  +%dk\n", $4, pn, n, int((d + 500) / 1000)
      } else {
        if (sid != "") printf "%s  span  %dk -> %dk\n", sid, int((first + 500) / 1000), int((prev + 500) / 1000)
        sid = $4; first = $2
      }
      prev = $2; pn = n
    }
    END { if (sid != "") printf "%s  span  %dk -> %dk\n", sid, int((first + 500) / 1000), int((prev + 500) / 1000) }
  '
}
