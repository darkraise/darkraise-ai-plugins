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
mkdir -p "$TMP/bin"
BASH_BIN=$(command -v bash)
# Every stub and shim below is interpreted via an absolute-path shebang, never
# "#!/usr/bin/env bash": once PATH is restricted to $TMP/bin, env has nothing
# left to resolve "bash" against and fails before the stub body ever runs.
make_stub() { printf '#!%s\necho "%s"\n' "$BASH_BIN" "$2" > "$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }

# PATH isolation has to be structural, not a coincidence of one machine's layout.
# A wide PATH hides the real executors only as long as none of them shares a
# directory with the script's own dependencies - and on most Linux distros both
# jq and codex land in /usr/bin, which would resolve the real binary and flip
# every not-present assertion. Shim just the commands the script needs, so
# PATH can be exactly one directory this test controls.
# dirname is external: both detect-executors.sh's HERE line and
# scripts/codex-plugin:16 call it, and a sealed PATH without it resolves HERE
# to the wrong directory and reports the plugin absent.
# cygpath is shimmed only where it exists: scripts/lib/native-path.sh probes for
# it and converts nothing without it, which is correct off Windows, so a stub
# standing in for an absent cygpath would test a path production never takes.
for dep in jq timeout head tr node bash dirname cygpath sort grep sed awk cat cut uname tail; do
  dep_path=$(command -v "$dep") || continue
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$dep_path" > "$TMP/bin/$dep"
  chmod +x "$TMP/bin/$dep"
done

# The locator reads a profile's settings and installed-plugins file; the version
# allowlist reads the policy file. run() below clears CLAUDE_PROJECT_DIR,
# because the locator also reads a project's own .claude/settings*.json.
# Required of every suite touching detect-executors.sh: a fixed session id and a
# temporary directory keep the machine's real session file out of every case.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=detect-test
export HOME="$TMP/home" DR_AGY_SESSION_DIR="$TMP/agy-sessions"
mkdir -p "$HOME"
jq -nc '{cli:"agy", min_version:"1.4.12", max_major:1, calibrated:"1.4.12", trust:{smoke:"fail"}}' > "$TMP/agy-policy.json"
STUB_PLUGIN="$HERE/fixtures/stub-codex-plugin"
mkdir -p "$TMP/config/plugins"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$TMP/config/settings.json"
jq -nc --arg p "$STUB_PLUGIN" \
  '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' \
  > "$TMP/config/plugins/installed_plugins.json"
jq -nc '{plugin:"codex@openai-codex", min_version:"1.0.3", max_major:1,
         trust:{calibration:"pending", smoke:"pending"}}' > "$TMP/policy.json"

# The codex row is probed through the plugin now, not through a codex binary on
# PATH, so PATH stays sealed to $TMP/bin and the locator is pointed at fixtures
# instead. CLAUDE_PROJECT_DIR is cleared because scripts/codex-plugin also reads
# a project's own .claude/settings*.json.
run() { PATH="$TMP/bin" CLAUDE_CONFIG_DIR="$TMP/config" CLAUDE_PROJECT_DIR= \
        DR_CODEX_POLICY="$TMP/policy.json" STUB_MODE="${STUB_MODE:-ok}" \
        DR_AGY_POLICY="$TMP/agy-policy.json" STUB_AGY_VERSION="${STUB_AGY_VERSION:-1.4.12}" \
        STUB_AGY_AUTH="${STUB_AGY_AUTH:-ok}" "$BASH_BIN" "$SCRIPT"; }
field() { jq -r --arg i "$1" --arg f "$2" '.[] | select(.id==$i) | .[$f]' <<< "$3"; }

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# --- nothing installed ------------------------------------------------------
out=$(run)
check "empty PATH: emits valid JSON" "$(jq -e 'type=="array"' >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "empty PATH: reports the four executors by id" \
  "$(jq -r '[.[].id] | sort | join(",")' <<<"$out")" "agy,codex,cursor-agent,opencode"
# No plugin enabled in the fixture profile, so there is no codex lane at all.
printf '{"enabledPlugins":{}}\n' > "$TMP/config/settings.json"
out=$(run)
check "no plugin: codex not present" "$(field codex present "$out")" "false"
check "no plugin: codex not usable" "$(field codex usable "$out")" "false"
check "no plugin: the reason names the plugin, not PATH" \
  "$(field codex reason "$out" | grep -qi 'plugin' && echo yes || echo no)" "yes"

# A locator that refuses for a reason other than enablement must say which one.
# Reporting every refusal as "not enabled" sends the reader to enable a plugin
# that is already enabled, which is the one thing they cannot fix.
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$TMP/config/settings.json"
cp -r "$STUB_PLUGIN" "$TMP/stub-9.9.9"
printf '{"name":"codex","version":"9.9.9"}\n' > "$TMP/stub-9.9.9/.claude-plugin/plugin.json"
jq -nc --arg p "$TMP/stub-9.9.9" \
  '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"9.9.9"}]}}' \
  > "$TMP/config/plugins/installed_plugins.json"
out=$(run)
check "an untrusted version is not usable" "$(field codex usable "$out")" "false"
check "an untrusted version names the version, not enablement" \
  "$(field codex reason "$out" | grep -c '9\.9\.9')" "1"
check "an untrusted version does not claim the plugin is disabled" \
  "$(field codex reason "$out" | grep -ci 'not enabled')" "0"
jq -nc --arg p "$STUB_PLUGIN" \
  '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' \
  > "$TMP/config/plugins/installed_plugins.json"

# --- codex enabled and logged in, both answered by the plugin ----------------
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$TMP/config/settings.json"
out=$(run)
check "codex present from the plugin" "$(field codex present "$out")" "true"
check "codex version from the plugin" "$(field codex version "$out")" "1.0.3"
check "codex authed from the plugin" "$(field codex authed "$out")" "true"
check "codex batch capable" "$(field codex batch_capable "$out")" "true"
check "codex usable" "$(field codex usable "$out")" "true"
check "usable executor carries no reason" "$(field codex reason "$out")" "null"

# --- enabled but logged out, and a probe that fails outright -----------------
out=$(STUB_MODE=logged-out run)
check "logged out is not usable" "$(field codex usable "$out")" "false"
check "logged out says so" \
  "$(field codex reason "$out" | grep -qi 'logged in' && echo yes || echo no)" "yes"
check "logged out is explicit" "$(field codex auth_status "$out")" "logged_out"
out=$(STUB_MODE=throw run 2>"$TMP/probe.err")
check "a failed probe is distinct" "$(field codex auth_status "$out")" "probe_failed"
check "a failed probe is unusable" "$(field codex usable "$out")" "false"
check "the probe's own text is not exposed" \
  "$(printf '%s%s' "$out" "$(cat "$TMP/probe.err")" | grep -c 'stub: app-server exploded')" "0"

# --- the probe is handed a working directory the platform can use -----------
# The codex plugin passes this cwd straight to spawnSync. Under Git Bash $PWD
# is a POSIX path, which Windows cannot resolve: spawnSync fails with ENOENT
# and the plugin reports {available:false, detail:"not found"} - the same shape
# a missing binary produces. The roster then reads probe_failed and the whole
# lane disappears with a reason naming the wrong cause.
expected_cwd="$PWD"
command -v cygpath >/dev/null 2>&1 && expected_cwd=$(cygpath -m "$PWD")
: > "$TMP/cwd.log"
STUB_EVENT_LOG="$TMP/cwd.log" run >/dev/null
check "the auth probe receives a native-form cwd" \
  "$(sed -n 's/^getCodexAuthStatus //p' "$TMP/cwd.log" | head -1)" "$expected_cwd"

# --- agy is a registered executor, and antigravity has no row ----------------
# The old antigravity row said its only agent mode opens a GUI session. agy is
# the headless Antigravity CLI, so a registered lane replaces that row instead
# of a PATH probe sitting beside it.
install_agy() { printf '#!%s\nexec "%s" "%s" "$@"\n' "$BASH_BIN" "$BASH_BIN" "$HERE/fixtures/stub-agy/agy" > "$TMP/bin/agy"; chmod +x "$TMP/bin/agy"; }
make_stub antigravity "Antigravity 1.107.0"
out=$(run)
check "an antigravity binary adds no row" "$(jq '[.[] | select(.id == "antigravity")] | length' <<<"$out")" "0"
rm -f "$TMP/bin/antigravity"

check "agy absent is not present" "$(field agy present "$out")" "false"
check "agy absent is not usable" "$(field agy usable "$out")" "false"
check "agy absent uses the entry's not_installed reason" \
  "$(field agy reason "$out")" "agy is not on PATH; install the Antigravity CLI"

install_agy
out=$(run)
check "agy present from its locator" "$(field agy present "$out")" "true"
check "agy version from its locator" "$(field agy version "$out")" "1.4.12"
check "agy is batch capable" "$(field agy batch_capable "$out")" "true"
check "agy yields exactly one row" "$(jq '[.[] | select(.id == "agy")] | length' <<<"$out")" "1"
check "the agy row's path is the directory holding agy" "$(field agy path "$out" | grep -c '/bin$')" "1"
out=$(STUB_AGY_VERSION=0.9.0 run)
check "an agy below the version floor is not usable" "$(field agy usable "$out")" "false"
check "an agy below the version floor names the version" "$(field agy reason "$out" | grep -c '0\.9\.0')" "1"

# The auth probe spawns agy from Node, which cannot run a bash-script stub on
# Windows.
SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$TMP/bin/agy" 2>/dev/null | tr -d '\r')
if [ "$SPAWNABLE" = yes ]; then
  out=$(run)
  check "agy authed from its probe" "$(field agy authed "$out")" "true"
  check "agy is usable" "$(field agy usable "$out")" "true"
  check "a usable agy carries no reason" "$(field agy reason "$out")" "null"
  out=$(STUB_AGY_AUTH=logged-out run)
  check "a signed-out agy is explicit" "$(field agy auth_status "$out")" "logged_out"
  check "a signed-out agy is not usable" "$(field agy usable "$out")" "false"
  check "a signed-out agy uses the entry's remedy" "$(field agy reason "$out" | grep -c 'run agy and sign in')" "1"
  out=$(STUB_AGY_AUTH=broken run)
  check "an agy whose models call fails is a failed probe" "$(field agy auth_status "$out")" "probe_failed"
  check "a failed agy probe uses the entry's reason" "$(field agy reason "$out" | grep -c 'agy models')" "1"
else
  printf 'skip - the agy probe cases: Node cannot run the bash-script stub on this platform\n'
fi
rm -f "$TMP/bin/agy"

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
nojq_out=$(PATH="$TMP/nojq" "$BASH_BIN" "$SCRIPT" 2>"$TMP/nojq.err")
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

# --- the roster row carries a plugin root and no catalog ---------------------
row=$(run | jq -c '.[] | select(.id=="codex")')
check "codex row: no advertised field" "$(jq -r 'has("advertised")' <<<"$row")" "false"
check "codex row: path is the plugin root, not a binary" \
  "$(jq -r '.path' <<<"$row" | grep -c 'stub-codex-plugin')" "1"

row=$(STUB_MODE=logged-out run | jq -c '.[] | select(.id=="codex")')
check "logged out: names the plugin setup command, not codex login" \
  "$(jq -r '.reason' <<<"$row" | grep -c 'codex:setup')" "1"

# --- the roster is driven by the registry ----------------------------------
# A registry id is probed through its own locator and probe, and its reasons
# come from its entry. A registered id must also suppress its PATH-probe row:
# two rows with one id would break every consumer that selects by id.
FIXREG="$HERE/fixtures/executors"
regrun() { PATH="$TMP/bin" CLAUDE_CONFIG_DIR="$TMP/config" CLAUDE_PROJECT_DIR= \
           DR_CODEX_POLICY="$TMP/policy.json" DR_EXECUTORS_DIR="$FIXREG" \
           STUB_MODE="${STUB_MODE:-ok}" "$BASH_BIN" "$SCRIPT"; }

out=$(regrun)
check "the stub executor appears in the roster" "$(field stub present "$out")" "true"
check "the stub executor is usable" "$(field stub usable "$out")" "true"
check "the stub executor is batch capable by virtue of its wrapper" \
  "$(field stub batch_capable "$out")" "true"
check "a usable registry executor carries no reason" "$(field stub reason "$out")" "null"
check "the stub row's path is its locator root" \
  "$(field stub path "$out" | grep -c 'fixtures/executors')" "1"

out=$(STUB_LOCATOR=off regrun)
check "a locator that reports off is not present" "$(field stub present "$out")" "false"
check "an off locator uses the entry's not_enabled reason" \
  "$(field stub reason "$out")" "the stub executor is not enabled in this profile"

out=$(STUB_PROBE=logged-out regrun)
check "a logged-out probe is explicit" "$(field stub auth_status "$out")" "logged_out"
check "a logged-out executor is not usable" "$(field stub usable "$out")" "false"
check "a logged-out executor uses the entry's remedy" \
  "$(field stub reason "$out" | grep -c '/stub:setup')" "1"

out=$(STUB_PROBE=throw regrun)
check "a probe without authed is a failed probe" "$(field stub auth_status "$out")" "probe_failed"
check "a failed probe uses the entry's probe_failed reason" \
  "$(field stub reason "$out" | grep -c '/stub:setup')" "1"

# A registered id suppresses its PATH row even when the binary is on PATH.
make_stub opencode "opencode 1.0.0"
out=$(regrun)
check "a registered id yields exactly one row" \
  "$(jq '[.[] | select(.id == "opencode")] | length' <<<"$out")" "1"
check "the registered opencode row is lane-implemented" \
  "$(field opencode usable "$out")" "true"
rm -f "$TMP/bin/opencode"

# An unregistered batch-capable id keeps the PATH probe and its missing-lane
# reason, which must name the registry rather than assert codex is unique.
make_stub cursor-agent "cursor-agent 1.0.0"
out=$(regrun)
check "an unregistered id is still not usable" "$(field cursor-agent usable "$out")" "false"
check "the missing-lane reason names the registry" \
  "$(field cursor-agent reason "$out" | grep -c 'executors list')" "1"
rm -f "$TMP/bin/cursor-agent"

# The probe receives a native-form cwd, as the codex probe does.
: > "$TMP/probe-cwd.log"
STUB_PROBE_LOG="$TMP/probe-cwd.log" regrun >/dev/null
expected_cwd="$PWD"
command -v cygpath >/dev/null 2>&1 && expected_cwd=$(cygpath -m "$PWD")
check "a registry probe receives a native-form cwd" \
  "$(head -1 "$TMP/probe-cwd.log")" "$expected_cwd"

# A cwd holding a quote and a backslash reaches the probe as valid JSON.
# Windows does not allow either in a file name.
if ! command -v cygpath >/dev/null 2>&1; then
  odd="$TMP/a\"b\\c"
  mkdir -p "$odd"
  : > "$TMP/probe-odd.log"
  (cd "$odd" && STUB_PROBE_LOG="$TMP/probe-odd.log" regrun >/dev/null)
  check "a cwd with a quote and a backslash reaches the probe intact" \
    "$(head -1 "$TMP/probe-odd.log")" "$odd"
fi
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
