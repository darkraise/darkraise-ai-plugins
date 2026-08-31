#!/usr/bin/env bash
# Detection must be honest about three distinct states: absent, present but not
# batch-capable, and usable. Conflating the middle state with either neighbour
# is the failure that matters - it either hides a tool the user asked about or
# offers one that cannot be dispatched.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/detect-executors.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# A synthetic PATH holding only the stubs we choose, so the result does not
# depend on what happens to be installed on the machine running the suite.
mkdir -p "$TMP/bin" "$TMP/codexhome"
BASH_BIN=$(command -v bash)
# Every stub and shim below is interpreted via an absolute-path shebang, never
# "#!/usr/bin/env bash": once PATH is restricted to $TMP/bin, env has nothing
# left to resolve "bash" against and fails before the stub body ever runs.
make_stub() { printf '#!%s\necho "%s"\n' "$BASH_BIN" "$2" > "$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }

# PATH isolation has to be structural, not a coincidence of one machine's layout.
# A wide PATH hides the real executors only as long as none of them shares a
# directory with the script's own dependencies - and on most Linux distros both
# jq and codex land in /usr/bin, which would resolve the real binary and flip
# every not-present assertion. Shim just the four commands the script needs, so
# PATH can be exactly one directory this test controls.
for dep in jq timeout head tr; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$TMP/bin/$dep"
  chmod +x "$TMP/bin/$dep"
done
run() { PATH="$TMP/bin" CODEX_HOME="$TMP/codexhome" "$BASH_BIN" "$SCRIPT"; }
field() { jq -r --arg i "$1" --arg f "$2" '.[] | select(.id==$i) | .[$f]' <<< "$3"; }

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# --- nothing installed ------------------------------------------------------
out=$(run)
check "empty PATH: emits valid JSON" "$(jq -e 'type=="array"' >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "empty PATH: reports all four executors" "$(jq 'length' <<<"$out")" "4"
check "empty PATH: codex not present" "$(field codex present "$out")" "false"
check "empty PATH: codex not usable" "$(field codex usable "$out")" "false"
check "empty PATH: codex has a reason" \
  "$(field codex reason "$out" | grep -qi 'path' && echo yes || echo no)" "yes"

# --- codex installed and authenticated --------------------------------------
make_stub codex "codex-cli 0.151.0"
printf '{"tokens":{}}' > "$TMP/codexhome/auth.json"
out=$(run)
check "codex present" "$(field codex present "$out")" "true"
check "codex version captured" "$(field codex version "$out")" "codex-cli 0.151.0"
check "codex authed" "$(field codex authed "$out")" "true"
check "codex batch capable" "$(field codex batch_capable "$out")" "true"
check "codex usable" "$(field codex usable "$out")" "true"
check "usable executor carries no reason" "$(field codex reason "$out")" "null"

# --- codex installed but unauthenticated ------------------------------------
rm -f "$TMP/codexhome/auth.json"
out=$(run)
check "unauthenticated codex is not usable" "$(field codex usable "$out")" "false"
check "unauthenticated codex says so" \
  "$(field codex reason "$out" | grep -qi 'auth' && echo yes || echo no)" "yes"
printf '{"tokens":{}}' > "$TMP/codexhome/auth.json"

# --- antigravity is present but never dispatchable --------------------------
# Its only agent-shaped subcommand opens a GUI chat session: no output file, no
# completion signal, no exit code tied to the work. Present is not usable.
make_stub antigravity "Antigravity 1.107.0"
out=$(run)
check "antigravity present" "$(field antigravity present "$out")" "true"
check "antigravity not batch capable" "$(field antigravity batch_capable "$out")" "false"
check "antigravity not usable" "$(field antigravity usable "$out")" "false"
check "antigravity reason mentions the GUI" \
  "$(field antigravity reason "$out" | grep -qi 'gui' && echo yes || echo no)" "yes"

# --- invariant across every row ---------------------------------------------
out=$(run)
check "reason is set exactly when usable is false" \
  "$(jq '[.[] | select((.usable == false) != (.reason != null))] | length' <<<"$out")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
