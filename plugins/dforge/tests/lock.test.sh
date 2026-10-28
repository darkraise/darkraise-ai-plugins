#!/usr/bin/env bash
# lib/lock.sh: a reclaim removes only the lock instance it judged.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/lock.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LOCK="$TMP/x.lockd"

# The owner a reclaim read releases and exits while the reclaim checks it, and
# a new holder takes the lock in between: the reclaim must leave that lock be.
sleep 0 & gone=$!
wait "$gone"
mkdir "$LOCK"
printf '%s\n' "$gone" > "$LOCK/pid"
uname -n > "$LOCK/host"
kill() {
  if [ "$1" = -0 ] && [ "${2:-}" = "$gone" ]; then
    rm -f -- "$LOCK/pid" "$LOCK/host" && rmdir -- "$LOCK"
    mkdir "$LOCK" && : > "$LOCK/claim" && printf '%s\n' "$$" > "$LOCK/pid"
  fi
  command kill "$@"
}
dr_lock_reclaim "$LOCK"; status=$?
unset -f kill
check "a lock taken during the reclaim: not reclaimed" "$status" "1"
check "a lock taken during the reclaim: its holder keeps it" "$(cat "$LOCK/pid" 2>/dev/null)" "$$"
check "a lock taken during the reclaim: its claim stays" "$([ -e "$LOCK/claim" ] && echo yes || echo no)" "yes"
dr_lock_release "$LOCK"

# A dead owner's lock is still reclaimed.
mkdir "$LOCK"
printf '%s\n' "$gone" > "$LOCK/pid"
uname -n > "$LOCK/host"
dr_lock_reclaim "$LOCK"; status=$?
check "a dead owner's lock: reclaimed" "$status:$([ -e "$LOCK" ] && echo left || echo gone)" "0:gone"

# Where mkdir is not exclusive (uutils), a second reclaimer's mkdir of the
# guard answers 0 while another holds it: only the guard's claim decides.
mkdir "$LOCK"
printf '%s\n' "$gone" > "$LOCK/pid"
uname -n > "$LOCK/host"
mkdir "$LOCK.reclaim"
: > "$LOCK.reclaim/claim"
mkdir() {
  if [ "${2:-}" = "$LOCK.reclaim" ] && [ -d "$LOCK.reclaim" ]; then return 0; fi
  command mkdir "$@"
}
err="$(dr_lock_reclaim "$LOCK" 2>&1)"; status=$?
unset -f mkdir
check "a guard held by another reclaimer: not reclaimed" "$status:$([ -e "$LOCK" ] && echo left || echo gone)" "1:left"
check "a guard held by another reclaimer: its claim stays" "$([ -e "$LOCK.reclaim/claim" ] && echo yes || echo no)" "yes"
check "a guard held by another reclaimer: nothing printed" "$err" ""
rm -rf -- "$LOCK" "$LOCK.reclaim"

# A guard left claimed by a reclaimer killed inside it is reclaimed once old.
mkdir "$LOCK"
printf '%s\n' "$gone" > "$LOCK/pid"
uname -n > "$LOCK/host"
mkdir "$LOCK.reclaim"
: > "$LOCK.reclaim/claim"
err="$(DR_LOCK_STALE_SECONDS=-1 dr_lock_reclaim "$LOCK" 2>&1)"; status=$?
check "a stale claimed guard: the lock is reclaimed" "$status:$([ -e "$LOCK" ] && echo left || echo gone)" "0:gone"
check "a stale claimed guard: no guard is left" "$(ls -d "$LOCK".reclaim* 2>/dev/null | grep -c .)" "0"
check "a stale claimed guard: nothing printed" "$err" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
