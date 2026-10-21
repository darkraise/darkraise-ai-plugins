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

# dr_lock_old DIR — DIR last changed more than DR_LOCK_STALE_SECONDS ago. A
# claim or a reclaim takes milliseconds, so an ownerless lock or a guard this
# old was left by a process killed inside it; the margin covers a claimer
# stopped mid-claim (a suspended job, a sleeping laptop) and a file server's
# clock skew. Seconds, not find -mmin, whose rounding differs between finds and
# can hold a writer off for two minutes.
DR_LOCK_STALE_SECONDS=${DR_LOCK_STALE_SECONDS:-30}
dr_lock_old() {
  local changed
  changed="$(stat -c %Y -- "$1" 2>/dev/null || stat -f %m -- "$1" 2>/dev/null)" || return 1
  [[ $changed =~ ^[0-9]+$ ]] && [ $(( $(date +%s) - changed )) -gt "$DR_LOCK_STALE_SECONDS" ]
}

# dr_lock_reclaim DIR — remove DIR when its owner provably exited: same host,
# and its PID is gone or names a process started at another time. A lock with
# no pid is taken once it is old. Reclaims are serialized so one cannot remove
# a lock another reclaimer just took.
dr_lock_reclaim() {
  local lock="$1" guard="$1.reclaim" aside pid host start now stale=1
  if ! mkdir -- "$guard" 2>/dev/null; then
    # Set aside before it is judged, so a guard taken since is given back.
    aside="$guard.stale-$$"
    dr_lock_old "$guard" && mv -- "$guard" "$aside" 2>/dev/null || return 1
    if ! dr_lock_old "$aside"; then
      [ -e "$guard" ] || mv -- "$aside" "$guard" 2>/dev/null
      return 1
    fi
    rmdir -- "$aside" 2>/dev/null
    mkdir -- "$guard" 2>/dev/null || return 1
  fi
  pid="$(cat "$lock/pid" 2>/dev/null)"
  host="$(cat "$lock/host" 2>/dev/null)"
  start="$(cat "$lock/start" 2>/dev/null)"
  if [ -d "$lock" ] && [ -z "$pid" ]; then
    dr_lock_old "$lock" && stale=0
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

# dr_link_target FILE — FILE with its symbolic links followed to the file they
# name, which need not exist; fails on a loop.
dr_link_target() {
  local file="$1" target hops=0
  while [ -L "$file" ]; do
    [ $((++hops)) -le 40 ] || return 1
    target="$(readlink -- "$file")" || return 1
    case $target in /*) file=$target ;; *) file="$(dirname "$file")/$target" ;; esac
  done
  printf '%s\n' "$file"
}

# dr_replace FILE SOURCE — replace FILE with SOURCE's content through a
# dotfile beside FILE: the rename is atomic (a temp file elsewhere may sit on
# another filesystem), darkmem never syncs the partial copy, and FILE keeps
# its mode. A symbolic link is written through: its target is replaced and the
# link stays.
dr_replace() {
  local file tmp
  file="$(dr_link_target "$1")" || return 1
  tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")" || return 1
  { [ ! -e "$file" ] || cp -p -- "$file" "$tmp"; } && cat -- "$2" > "$tmp" && mv -f -- "$tmp" "$file" ||
    { rm -f -- "$tmp"; return 1; }
}

# dr_lock_base FILE — the path FILE's lock is named from, after its links are
# followed, so a link and its target share one lock: inside the git
# directory for a file in a checkout, where a lock never shows as an untracked
# file, else a dotfile beside FILE, which darkmem never syncs.
dr_lock_base() {
  local file dir name common key
  file="$(dr_link_target "$1")" || return 1
  dir="$(cd -P "$(dirname "$file")" && pwd -P)" || return 1
  name="$(basename "$file")"
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
# status, or 1 when the lock is not had within DR_LOCK_TENTHS tenths or flock
# fails for another reason; the message says which.
dr_locked() {
  local base="$1" status i claimed=0
  shift
  if command -v "${DFORGE_FLOCK:-flock}" >/dev/null 2>&1; then
    (
      # 75 is no code flock itself uses, so only a timeout reads as a busy lock.
      "${DFORGE_FLOCK:-flock}" -w $(( (DR_LOCK_TENTHS + 9) / 10 )) -E 75 9
      status=$?
      case $status in
        0) ;;
        75) echo "dforge: $base is locked by another process" >&2; exit 1 ;;
        *) echo "dforge: cannot lock $base (flock exited $status)" >&2; exit 1 ;;
      esac
      "$@"
    ) 9>>"$base.lock"
    return
  fi
  for ((i = 0; i <= DR_LOCK_TENTHS; i++)); do
    if mkdir -- "$base.lockd" 2>/dev/null ||
       { dr_lock_reclaim "$base.lockd" && mkdir -- "$base.lockd" 2>/dev/null; }; then
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
