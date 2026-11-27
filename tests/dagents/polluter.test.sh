#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../plugins/dagents/skills/systematic-debugging/references/find-polluter.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo/src"
cat > "$TMP/bin/npm" <<'STUB'
#!/usr/bin/env bash
printf 'ran\n' >> "$POLLUTER_CALLS"
[ -z "${POLLUTER_ARGS:-}" ] || printf '%s\n' "${@: -1}" >> "$POLLUTER_ARGS"
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
out=$(cd "$TMP/repo" && bash "$SCRIPT" pollution); rc=$?
check 'usage error is inconclusive, not a polluter' "$rc" 2
fresh() { rm -rf "$TMP/r" "$TMP/args"; mkdir -p "$TMP/r"; }
fresh; mkdir -p "$TMP/r/src"; touch "$TMP/r/src/a b.test.ts"
out=$(cd "$TMP/r" && POLLUTER_ARGS="$TMP/args" bash "$SCRIPT" pollution 'src/**/*.test.ts'); rc=$?
check 'a test path with a space runs as one file' "$rc|$(cat "$TMP/args" 2>/dev/null)" "0|./src/a b.test.ts"
fresh; mkdir -p "$TMP/r/src" "$TMP/r/node_modules/pkg" "$TMP/r/.git/hooks"
touch "$TMP/r/src/a.test.ts" "$TMP/r/node_modules/pkg/x.test.ts" "$TMP/r/.git/hooks/y.test.ts"
out=$(cd "$TMP/r" && POLLUTER_ARGS="$TMP/args" bash "$SCRIPT" pollution '**/*.test.ts'); rc=$?
check 'node_modules and .git tests are never run' "$(cat "$TMP/args" 2>/dev/null)" "./src/a.test.ts"
fresh; mkdir -p "$TMP/r/src" "$TMP/failbin"; touch "$TMP/r/src/a.test.ts"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$TMP/failbin/npm"; chmod +x "$TMP/failbin/npm"
out=$(cd "$TMP/r" && PATH="$TMP/failbin:$PATH" bash "$SCRIPT" pollution 'src/**/*.test.ts'); rc=$?
check 'every failing run is inconclusive' "$rc|$(grep -c 'no diagnosis performed' <<<"$out")|$(grep -cF 'all tests clean' <<<"$out")" "2|1|0"
fresh; mkdir -p "$TMP/r/src"; touch "$TMP/r/src/a.test.ts"
cat > "$TMP/bin/runner" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$POLLUTER_ARGS"
touch pollution
STUB
chmod +x "$TMP/bin/runner"
before=$(wc -l < "$TMP/calls" | tr -d ' ')
out=$(cd "$TMP/r" && POLLUTER_ARGS="$TMP/args" bash "$SCRIPT" pollution 'src/**/*.test.ts' "$TMP/bin/runner --flag"); rc=$?
check 'the third argument names the test command' \
  "$rc|$(grep -c 'Test: ./src/a.test.ts' <<<"$out")|$(cat "$TMP/args" 2>/dev/null)|$(( $(wc -l < "$TMP/calls" | tr -d ' ') - before ))" \
  "1|1|--flag ./src/a.test.ts|0"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
