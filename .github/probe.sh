#!/usr/bin/env bash
# CI-only probe: the mkdir lock race and GNU timeout's escalation.
set -u
LIB="$PWD/plugins/dforge/scripts/lib/lock.sh"
echo "== env"; uname -a; bash --version | head -1; timeout --version | head -1
ps -o pid,ppid,pgid,sid,cmd -p $$; echo "self stat: $(cat /proc/$$/stat)"
W=$(mktemp); cat > "$W" <<'EOW'
. "$LIB"
exec 7>>"$1/trace.$$"; BASH_XTRACEFD=7
f="$1/count"
bump() { local n; n=$(cat "$f"); sleep 0.3; echo $((n + 1)) > "$f"; }
set -x
DFORGE_FLOCK=no-such-flock dr_locked "$1/.count" bump
EOW
export LIB
bad=0
for i in $(seq 1 30); do
  d=$(mktemp -d); echo 0 > "$d/count"
  bash "$W" "$d" & bash "$W" "$d" & wait
  r=$(cat "$d/count")
  if [ "$r" != 2 ]; then
    bad=$((bad + 1)); echo "== race $i: count $r"
    for t in "$d"/trace.*; do echo "-- $t"; grep -E "mkdir|reclaim|kill|proc_start|lock_old|stat|rmdir|date|cat .*/(pid|host|start)|stale|return" "$t" | head -80; done
  fi
  rm -rf "$d"
done
echo "== race: $bad of 30 lost an update"
echo "== timeout"
d=$(mktemp -d); start=$(date +%s.%N)
timeout -k 1 1 bash -c 'trap "" TERM; sleep 20 & echo $! > "$0"; ps -o pid,ppid,pgid,sid,cmd -p $$,$! ; wait' "$d/pid" > "$d/out" 2>&1 < /dev/null &
tp=$!; sleep 0.3; ps -o pid,ppid,pgid,sid,cmd -p $tp; wait $tp; echo "timeout exit $?"
end=$(date +%s.%N); awk -v a="$start" -v b="$end" 'BEGIN { printf "elapsed %.1fs\n", b - a }'; cat "$d/out"
p=$(cat "$d/pid"); if kill -0 "$p" 2>/dev/null; then echo "sleep $p still alive"; ps -o pid,ppid,pgid,sid,cmd -p "$p"; kill "$p"; else echo "sleep $p gone"; fi
