# Sourced. Locks for a read-modify-write of a shared file: flock where it
# exists, else a lock directory that records its owner. Defines functions only.

DR_LOCK_TENTHS=${DR_LOCK_TENTHS:-100}

# dr_proc_start PID — when PID's process started, so a reused PID reads as a
# different process; empty where neither /proc nor `ps -o lstart` exists.
dr_proc_start() {
  if [ -r "/proc/$1/stat" ]; then
    # The command name in field 2 may hold spaces, so count from its ")".
    sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
  else
    ps -o lstart= -p "$1" 2>/dev/null
  fi
}

# dr_lock_claim DIR — record this shell as the owner of the lock directory DIR
# it just created. The pid is written last: a lock without one is unowned.
dr_lock_claim() {
  dr_proc_start "$$" > "$1/start" || true
  if ! { uname -n > "$1/host" && printf '%s\n' "$$" > "$1/pid"; }; then
    rm -f -- "$1/start" "$1/host" "$1/pid"; rmdir -- "$1" 2>/dev/null
    return 1
  fi
}

# dr_lock_release DIR — remove DIR when this shell owns it.
dr_lock_release() {
  [ "$(cat "$1/pid" 2>/dev/null)" = "$$" ] || return 1
  rm -f -- "$1/pid" "$1/start" "$1/host"
  rmdir -- "$1"
}

# dr_lock_reclaim DIR [UNOWNED] — remove DIR when its owner provably exited:
# same host, and its PID is gone or names a process started at another time.
# With UNOWNED 1, a lock with no owner record is taken too; only a caller that
# waited far longer than a claim takes passes it. Reclaims are serialized so
# one cannot remove a lock another reclaimer just took.
dr_lock_reclaim() {
  local lock="$1" guard="$1.reclaim" pid host start now stale=1
  mkdir -- "$guard" 2>/dev/null || return 1
  pid="$(cat "$lock/pid" 2>/dev/null)"
  host="$(cat "$lock/host" 2>/dev/null)"
  start="$(cat "$lock/start" 2>/dev/null)"
  if [ -d "$lock" ] && [ -z "$pid" ] && [ -z "$host" ] && [ "${2:-0}" = 1 ]; then
    stale=0
  elif [[ "$pid" =~ ^[0-9]+$ ]] && [ -n "$host" ] && [ "$host" = "$(uname -n)" ]; then
    if ! kill -0 "$pid" 2>/dev/null; then
      stale=0
    else
      now="$(dr_proc_start "$pid")"
      [ -n "$start" ] && [ -n "$now" ] && [ "$now" != "$start" ] && stale=0
    fi
  fi
  if [ "$stale" -eq 0 ]; then
    rm -f -- "$lock/pid" "$lock/start" "$lock/host"
    rmdir -- "$lock" 2>/dev/null || stale=1
  fi
  rmdir -- "$guard"
  return "$stale"
}

# dr_lock_base FILE — the path FILE's lock is named from: inside the git
# directory for a file in a checkout, where a lock never shows as an untracked
# file, else a dotfile beside FILE, which darkmem never syncs.
dr_lock_base() {
  local dir name common key
  dir="$(cd "$(dirname "$1")" && pwd -P)" || return 1
  name="$(basename "$1")"
  if common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    key="$(printf '%s' "$dir/$name" | git -C "$dir" hash-object --stdin)" || return 1
    mkdir -p -- "$common/dforge/locks" || return 1
    printf '%s/dforge/locks/%s.%s\n' "$common" "$name" "${key:0:12}"
  else
    printf '%s/.%s\n' "$dir" "$name"
  fi
}

# dr_locked BASE COMMAND [ARGS…] — run COMMAND in a subshell holding BASE's
# lock: flock on BASE.lock, else the directory BASE.lockd. Returns COMMAND's
# status, or 1 when the lock is not had within DR_LOCK_TENTHS tenths.
dr_locked() {
  local base="$1" status i claimed=0
  shift
  if command -v "${DFORGE_FLOCK:-flock}" >/dev/null 2>&1; then
    (
      "${DFORGE_FLOCK:-flock}" -w $(( (DR_LOCK_TENTHS + 9) / 10 )) 9 || { echo "dforge: $base is locked by another process" >&2; exit 1; }
      "$@"
    ) 9>>"$base.lock"
    return
  fi
  for ((i = 0; i <= DR_LOCK_TENTHS; i++)); do
    if mkdir -- "$base.lockd" 2>/dev/null ||
       { dr_lock_reclaim "$base.lockd" "$(( i == DR_LOCK_TENTHS ))" && mkdir -- "$base.lockd" 2>/dev/null; }; then
      claimed=1; break
    fi
    [ "$i" -eq "$DR_LOCK_TENTHS" ] || sleep 0.1
  done
  [ "$claimed" -eq 1 ] && dr_lock_claim "$base.lockd" || { echo "dforge: $base is locked by another process" >&2; return 1; }
  ( "$@" )
  status=$?
  dr_lock_release "$base.lockd"
  return "$status"
}
