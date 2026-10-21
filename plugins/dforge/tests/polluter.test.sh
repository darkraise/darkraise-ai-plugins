#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../skills/systematic-debugging/references/find-polluter.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo/src"
cat > "$TMP/bin/npm" <<'STUB'
#!/usr/bin/env bash
printf 'ran\n' >> "$POLLUTER_CALLS"
STUB
chmod +x "$TMP/bin/npm"
export PATH="$TMP/bin:$PATH" POLLUTER_CALLS="$TMP/calls"
pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}
touch "$TMP/repo/src/a.test.ts" "$TMP/repo/pollution"
out=$(cd "$TMP/repo" && bash "$SCRIPT" pollution 'src/**/*.test.ts'); rc=$?
check 'polluted baseline is inconclusive' "$rc" 2
check 'polluted baseline never reports clean' "$(grep -cF 'all tests clean' <<<"$out")" 0
check 'polluted baseline runs no tests' "$([ -e "$TMP/calls" ] && echo yes || echo no)" no
rm "$TMP/repo/pollution"
out=$(cd "$TMP/repo" && bash "$SCRIPT" pollution 'missing/*.test.ts'); rc=$?
check 'empty selection is inconclusive' "$rc" 2
out=$(cd "$TMP/repo" && bash "$SCRIPT" pollution 'src/**/*.test.ts'); rc=$?
check 'clean run succeeds' "$rc" 0
check 'clean run actually executes a test' "$(wc -l < "$TMP/calls" | tr -d ' ')" 1
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
