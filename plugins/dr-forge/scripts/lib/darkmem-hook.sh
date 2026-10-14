# Sourced. darkmem sync from the Claude Code hooks (darkmem store options spec
# §5): reconcile and pull at session start, a silent push at Stop. Defines
# functions only; each returns 0 whatever happens, since a hook must never fail
# on a sync. The session id is exported into every darkmem-sync call, so the
# run darkmem records is the session's, not the per-directory fallback.

. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"
_DARKMEM_HOOK_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Neither file means no mapping and nothing in a mirror, and costs no node
# start: the common case for a repository that never used darkmem.
_darkmem_configured() {
  command -v node >/dev/null 2>&1 || return 1
  [ -f "${HOME:-}/.dr-forge/config.json" ] || [ -f "${HOME:-}/.dr-forge/stores.json" ]
}

# _darkmem_watchdog SECONDS CMD... — CMD, killed with its children after
# SECONDS, where GNU timeout is missing (macOS ships none): an async hook's
# timeout is not enforced, so nothing else would stop it. set -m starts CMD in
# its own process group, which the kill takes whole, node included. SIGTERM
# first, SIGKILL after the grace period (DARKMEM_KILL_GRACE, 5 s) for a command
# that ignores it.
_darkmem_watchdog() {
  local seconds=$1 pid watchdog status monitor=1
  case $- in *m*) ;; *) monitor=0 ;; esac
  shift
  set -m
  "$@" &
  pid=$!
  (sleep "$seconds"; kill -TERM -- "-$pid"; sleep "${DARKMEM_KILL_GRACE:-5}"; kill -KILL -- "-$pid") >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" 2>/dev/null
  status=$?
  kill -TERM -- "-$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  [ "$monitor" = 1 ] || set +m
  return "$status"
}

# _darkmem_bounded SECONDS CMD... — CMD under GNU timeout, else the watchdog;
# both escalate to SIGKILL after the same grace period.
_darkmem_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout -k "${DARKMEM_KILL_GRACE:-5}" "$@"
  else
    _darkmem_watchdog "$@"
  fi
}

# _darkmem_run DIR SID SECONDS COMMAND — darkmem-sync COMMAND in DIR, bounded.
_darkmem_run() {
  (cd "$1" 2>/dev/null && export DR_FORGE_SESSION_ID=$2 && _darkmem_bounded "$3" bash "$_DARKMEM_HOOK_SCRIPTS/darkmem-sync" "$4" </dev/null)
}

# _darkmem_fit MAXLINES MAXCHARS — the lines on stdin, fitted. Every unindented
# line (a family's reconcile line, a conflict, a failure, a summary) is kept, in
# order, while the character room holds it; indented detail lines fill what is
# left of both rooms; one closing line counts what was left out. 100 characters
# stay free for that line.
_darkmem_fit() {
  awk -v maxlines="$1" -v maxchars="$2" '
    { line[NR] = $0; detail[NR] = ($0 ~ /^[ \t]/) }
    END {
      room = maxchars - 100
      for (i = 1; i <= NR; i++) {
        if (detail[i]) { details++; continue }
        size = length(line[i]) + 1
        if (used + size <= room) { keep[i] = 1; used += size; tops++ }
      }
      slots = maxlines - tops
      if (details > slots) slots--
      for (i = 1; i <= NR; i++) {
        if (!detail[i] || slots <= 0) continue
        size = length(line[i]) + 1
        if (used + size <= room) { keep[i] = 1; used += size; slots--; shown++ }
      }
      for (i = 1; i <= NR; i++) if (keep[i]) print line[i]
      if (NR > tops + shown) printf "darkmem-sync: %d more lines; run darkmem-sync reconcile or status to see them\n", NR - tops - shown
    }'
}

# darkmem_session_lines DIR SID [ROOM] — reconcile's and pull's lines for the
# session start note, without notes, "nothing to pull" or a pull summary that
# reports nothing, fitted to 20 lines and ROOM characters (default: no
# character limit). A malformed config prints its one-line reason instead. A
# repository that is disabled or unmapped still reconciles while a family is in
# the mirror, so that family moves back.
darkmem_session_lines() {
  local reason status
  _darkmem_configured || return 0
  reason=$( (forge_docs_store "$1" >/dev/null) 2>&1 )
  status=$?
  [ "$status" = 0 ] || { printf '%s\n' "$reason" | head -n 1; return 0; }
  (forge_project "$1") >/dev/null 2>&1 \
    || [ "$( (forge_docs_store "$1") 2>/dev/null)" = darkmem ] \
    || [ "$( (forge_progress_store "$1") 2>/dev/null)" = darkmem ] \
    || return 0
  { _darkmem_run "$1" "$2" 200 reconcile 2>&1; _darkmem_run "$1" "$2" 60 pull 2>&1; } \
    | tr -d '\r' \
    | grep -v -e '^note:' -e 'nothing to pull' -e 'reconcile moves it back$' \
        -e '^darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures$' \
    | _darkmem_fit 20 "${3:-1000000}"
  return 0
}

# darkmem_push_quietly DIR SID — the background Stop push
# (scripts/darkmem-stop-push.sh). Nothing it prints would reach anyone. It
# refuses at once when the mirror lock is held (a wait of 1 ms; 0 would mean the
# 100 s default), so Stop pushes never queue up ahead of a skill's own push or
# the next session's reconcile; the next stop pushes what this one missed.
darkmem_push_quietly() {
  _darkmem_configured || return 0
  (forge_project "$1") >/dev/null 2>&1 || return 0
  DARKMEM_SYNC_LOCK_WAIT_MS=1 _darkmem_run "$1" "$2" 100 push >/dev/null 2>&1
  return 0
}
