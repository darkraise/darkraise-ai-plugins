#!/usr/bin/env bash
# CI-only probe: is mkdir exclusive under a race, and is bash's noclobber?
set -u
mkdir --version | head -1
d=$(mktemp -d); mkdir "$d/x"; mkdir "$d/x" 2>&1; echo "second mkdir of an existing dir: exit $?"
both=0
for i in $(seq 1 300); do
  rm -rf "$d/r"; ok=$(mktemp)
  for j in 1 2 3 4; do (mkdir "$d/r" 2>/dev/null && echo won >> "$ok") & done; wait
  [ "$(grep -c won "$ok")" -gt 1 ] && both=$((both + 1)); rm -f "$ok"
done
echo "mkdir: $both of 300 races had more than one winner"
both=0
for i in $(seq 1 300); do
  rm -f "$d/f"; ok=$(mktemp)
  for j in 1 2 3 4; do ( set -o noclobber; { : > "$d/f"; } 2>/dev/null && echo won >> "$ok") & done; wait
  [ "$(grep -c won "$ok")" -gt 1 ] && both=$((both + 1)); rm -f "$ok"
done
echo "noclobber: $both of 300 races had more than one winner"
