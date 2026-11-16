#!/usr/bin/env bash
# scripts/with-timeout and agy-locate on a host with only gtimeout.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../scripts"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
# A script that execs the tool by its absolute path, never a link or a copy:
# Git Bash's ln -s copies, and a copied .exe loses its DLLs; a uutils
# multicall binary picks its tool from the name it is run under.
wrap() { # wrap <name> <target>
  printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$2" > "$BIN/$1"; chmod +x "$BIN/$1"
}
for t in env sleep true cat head tr dirname basename jq sed grep; do wrap "$t" "$(type -P "$t")"; done
wrap gtimeout "$(command -v timeout)"
PATH="$BIN" "$BASH" "$S/with-timeout" 5 true; rc=$?
check "only gtimeout: a quick command exits 0" "$rc" "0"
PATH="$BIN" "$BASH" "$S/with-timeout" 1 sleep 5; rc=$?
check "only gtimeout: the bound exits 124" "$rc" "124"
V=$(jq -r .min_version < "$HERE/../reference/agy-policy.json" | tr -d '\r')
printf '#!%s\necho "%s"\n' "$BASH" "$V" > "$BIN/agy"; chmod +x "$BIN/agy"
out=$(timeout 30 env PATH="$BIN" "$BASH" "$S/agy-locate"); rc=$?
check "only gtimeout: agy-locate bounds agy --version and reports it ok" "$rc:$out" "0:agy-locate ok version=$V root=$BIN"
# The bound cut to 1 s, so a hang shows quickly.
printf '#!%s\nshift; exec "%s" 1 "$@"\n' "$BASH" "$(command -v timeout)" > "$BIN/gtimeout"; chmod +x "$BIN/gtimeout"
printf '#!%s\nexec sleep 60\n' "$BASH" > "$BIN/agy"; chmod +x "$BIN/agy"
out=$(timeout 30 env PATH="$BIN" "$BASH" "$S/agy-locate"); rc=$?
check "only gtimeout: an agy --version that hangs is a timeout, not a missing CLI" "$rc:$out" "1:agy-locate off reason=version-timeout"
rm -f "$BIN/gtimeout"
out=$(PATH="$BIN" "$BASH" "$S/with-timeout" 5 true 2>&1); rc=$?
check "no timeout command: exit 125" "$rc:$out" "125:with-timeout: no timeout command (timeout or gtimeout) on PATH"
printf '#!%s\nsleep 60\n' "$BASH" > "$BIN/agy"; chmod +x "$BIN/agy"
out=$(timeout 30 env PATH="$BIN" "$BASH" "$S/agy-locate"); rc=$?
check "agy-locate: no timeout command reports the CLI unusable" "$rc:$out" "1:agy-locate off reason=no-timeout-command"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
