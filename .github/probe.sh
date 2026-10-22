#!/usr/bin/env bash
set -u
echo "== proc start stability"
sleep 60 & p=$!
vals=$(for i in $(seq 1 200); do sed 's/^.*) //' "/proc/$p/stat" | awk '{print $20}'; done | sort | uniq -c)
echo "$vals"; kill "$p"
echo "self: $(for i in $(seq 1 50); do sed 's/^.*) //' "/proc/$$/stat" | awk '{print $20}'; done | sort -u | wc -l) distinct of 50"
echo "== awk and CR"
d=$(mktemp -d); printf 'a\r\nb\r\n' > "$d/f"
echo "file:     $(od -c "$d/f" | head -1)"
echo "awk file: $(awk '{ print }' "$d/f" | od -c | head -1)"
echo "cat|awk:  $(cat "$d/f" | awk '{ print }' | od -c | head -1)"
echo "BINMODE:  $(awk -v BINMODE=3 '{ print }' "$d/f" | od -c | head -1)"
echo "awk>file: $(awk '{ print }' "$d/f" > "$d/g"; od -c "$d/g" | head -1)"
echo "sed file: $(sed 's/x/y/' "$d/f" | od -c | head -1)"
awk --version | head -1; command -v awk
