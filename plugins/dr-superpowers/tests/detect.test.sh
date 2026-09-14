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
printf '#!%s\nif [[ "$*" == "--version" ]]; then echo "codex-cli 0.151.0"; else echo "Logged in using ChatGPT"; fi\n' "$BASH_BIN" > "$TMP/bin/codex"
chmod +x "$TMP/bin/codex"
out=$(run)
check "codex present" "$(field codex present "$out")" "true"
check "codex version captured" "$(field codex version "$out")" "codex-cli 0.151.0"
check "codex authed" "$(field codex authed "$out")" "true"
check "codex batch capable" "$(field codex batch_capable "$out")" "true"
check "codex usable" "$(field codex usable "$out")" "true"
check "usable executor carries no reason" "$(field codex reason "$out")" "null"

# --- codex installed but unauthenticated ------------------------------------
rm -f "$TMP/codexhome/auth.json"
printf '#!%s\nif [[ "$*" == "--version" ]]; then echo "codex-cli 0.151.0"; else echo "Not logged in"; exit 1; fi\n' "$BASH_BIN" > "$TMP/bin/codex"
printf '{"tokens":{}}' > "$TMP/codexhome/auth.json"
out=$(run)
check "unauthenticated codex is not usable" "$(field codex usable "$out")" "false"
check "unauthenticated codex says so" \
  "$(field codex reason "$out" | grep -qi 'auth' && echo yes || echo no)" "yes"
printf '{"tokens":{}}' > "$TMP/codexhome/auth.json"
check "logged out is explicit" "$(field codex auth_status "$out")" logged_out
printf '#!%s\nif [[ "$*" == "--version" ]]; then echo "codex-cli 0.151.0"; else echo "secret-example-token"; exit 9; fi\n' "$BASH_BIN" > "$TMP/bin/codex"
out=$(run 2>"$TMP/probe.err")
check "failed probe is distinct" "$(field codex auth_status "$out")" probe_failed
check "failed probe is unusable" "$(field codex usable "$out")" false
check "probe output is not exposed" "$(printf '%s%s' "$out" "$(cat "$TMP/probe.err")" | grep -c secret-example-token)" 0

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

# --- batch-capable tools with no lane ---------------------------------------
# Both CLIs can run a task headlessly, so batch_capable is honestly true, but
# this plugin ships a wrapper only for codex. Reporting them usable puts them in
# the plan header, where the executor line is then written from the
# codex-assignment block - a codex rung under a non-codex header, which the
# assigning skill's own final check rejects with nothing to fall back to.
for tool in cursor-agent opencode; do
  out=$(run)
  check "$tool absent is not usable" "$(field "$tool" usable "$out")" "false"
  make_stub "$tool" "$tool 1.0.0"
  out=$(run)
  check "$tool present" "$(field "$tool" present "$out")" "true"
  check "$tool is batch capable" "$(field "$tool" batch_capable "$out")" "true"
  check "$tool has no auth answer" "$(field "$tool" authed "$out")" "null"
  check "$tool is still not usable" "$(field "$tool" usable "$out")" "false"
  check "$tool reason names the missing lane" \
    "$(field "$tool" reason "$out" | grep -qi 'lane' && echo yes || echo no)" "yes"
done

# --- jq is a hard dependency, and its absence must be loud -------------------
# Without this guard the script exits 127 with empty stdout, which the
# dispatching skill reads as "no executor usable": the lane disappears with no
# message naming the cause.
mkdir -p "$TMP/nojq"
for dep in timeout head tr; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$TMP/nojq/$dep"
  chmod +x "$TMP/nojq/$dep"
done
nojq_out=$(PATH="$TMP/nojq" CODEX_HOME="$TMP/codexhome" "$BASH_BIN" "$SCRIPT" 2>"$TMP/nojq.err")
nojq_rc=$?
check "a missing jq exits 2" "$nojq_rc" "2"
check "a missing jq prints nothing on stdout" "$(printf '%s' "$nojq_out" | wc -c | tr -d ' ')" "0"
# The script's own message, not just the string "jq": a bare "jq: command not
# found" from the shell would satisfy a looser match, so the assertion would
# pass with the guard removed and prove nothing.
check "a missing jq says which dependency is absent" \
  "$(grep -qF 'detect-executors: jq is required' "$TMP/nojq.err" && echo yes || echo no)" "yes"

# --- invariant across every row ---------------------------------------------
out=$(run)
check "reason is set exactly when usable is false" \
  "$(jq '[.[] | select((.usable == false) != (.reason != null))] | length' <<<"$out")" "0"

# --- advertised model pairs --------------------------------------------------
# The cache is a negative filter: a pair it does not list is never attempted.
# It is not entitlement — gpt-5.6-luna and gpt-5.6-terra were listed on
# 2026-09-14 and were rejected with HTTP 400 on this account on 2026-08-31.
cat > "$TMP/bin/codex" <<STUB
#!$BASH_BIN
case "\$1" in
  login) echo "Logged in using ChatGPT" ;;
  *) echo "codex-cli 0.153.4" ;;
esac
STUB
chmod +x "$TMP/bin/codex"

write_cache() { printf '%s' "$1" > "$TMP/codexhome/models_cache.json"; }

write_cache '{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","models":[
  {"slug":"gpt-6-astra","visibility":"list","supported_reasoning_levels":[{"effort":"high"},{"effort":"xhigh"}]},
  {"slug":"gpt-5.6-sol","visibility":"list","supported_reasoning_levels":[{"effort":"high"}]},
  {"slug":"gpt-reserve","visibility":"hide","supported_reasoning_levels":[{"effort":"high"}]}]}'
out=$(run)
check "advertised: fetched_at" "$(field codex advertised "$out" | jq -r '.fetched_at')" "2026-09-14T13:35:00Z"
check "advertised: client_version" "$(field codex advertised "$out" | jq -r '.client_version')" "0.153.4"
check "advertised: astra/high is listed" \
  "$(field codex advertised "$out" | jq '[.pairs[] | select(.model=="gpt-6-astra" and .effort=="high")] | length')" "1"
check "advertised: hidden models are filtered out" \
  "$(field codex advertised "$out" | jq '[.pairs[] | select(.model=="gpt-reserve")] | length')" "0"
# jq -r prints "null" for a key that does not exist, so a value check alone
# would pass against the unmodified script. Assert the key is present too.
has_field() { jq -r --arg i "$1" --arg f "$2" '.[] | select(.id==$i) | has($f)' <<< "$3"; }
check "advertised: the key exists on every row" "$(has_field cursor-agent advertised "$out")" "true"
check "advertised: non-codex rows are null" "$(field cursor-agent advertised "$out")" "null"

# A cache that lists nothing is not the same fact as no cache at all.
write_cache '{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","models":[]}'
out=$(run)
check "advertised: empty catalog is an empty pair list" \
  "$(field codex advertised "$out" | jq -c '.pairs')" "[]"

write_cache 'not json at all'
out=$(run)
check "advertised: malformed cache is null" "$(field codex advertised "$out")" "null"
check "malformed cache still emits the key" "$(has_field codex advertised "$out")" "true"
check "malformed cache does not break the roster" \
  "$(jq -e 'type=="array"' >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"

# A half-written cache during a concurrent codex run: valid JSON followed by
# garbage. jq emits the object and then fails, so an unguarded extraction
# yields "{...}null", which --argjson rejects - and the whole codex row
# disappears from the roster, silently losing the lane.
write_cache '{"fetched_at":"x","client_version":"y","models":[]} trailing garbage'
out=$(run)
check "advertised: trailing garbage is null" "$(field codex advertised "$out")" "null"
check "trailing garbage keeps the codex row" \
  "$(jq -r '[.[] | select(.id=="codex")] | length' <<<"$out")" "1"

rm -f "$TMP/codexhome/models_cache.json"
out=$(run)
check "advertised: absent cache is null" "$(field codex advertised "$out")" "null"
check "absent cache still emits the key" "$(has_field codex advertised "$out")" "true"
check "absent cache leaves codex usable" "$(field codex usable "$out")" "true"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
