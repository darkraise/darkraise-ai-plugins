#!/usr/bin/env bash
# The session gate decides whether a session may touch Codex at all, so every
# way it can say no is asserted here - against a stub Claude config dir and a
# stub codex plugin whose app-server client is scripted per case. No case
# starts a real Codex.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# A config dir outside any git repository, so no project settings leak in.
CFG="$TMP/config"
PLUG="$TMP/plugin"
mkdir -p "$CFG/plugins" "$PLUG/.claude-plugin" "$PLUG/scripts/lib" "$TMP/work"
enable() { # enable <true|false|absent>
  case "$1" in
    absent) printf '{"enabledPlugins":{"other@x":true}}\n' > "$CFG/settings.json" ;;
    *) printf '{"enabledPlugins":{"codex@openai-codex":%s}}\n' "$1" > "$CFG/settings.json" ;;
  esac
}
install_plugin() { # install_plugin <registry-version> <manifest-version>
  printf '{"version":2,"plugins":{"codex@openai-codex":[{"scope":"user","installPath":"%s","version":"%s"}]}}\n' \
    "$PLUG" "$1" > "$CFG/plugins/installed_plugins.json"
  printf '{"name":"codex","version":"%s"}\n' "$2" > "$PLUG/.claude-plugin/plugin.json"
}

locate() { # locate; sets out and rc
  out=$(cd "$TMP/work" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR= bash "$P/scripts/codex-plugin" 2>"$TMP/err"); rc=$?
}

# --- the locator -------------------------------------------------------------
check "codex-plugin exists" "$([ -f "$P/scripts/codex-plugin" ] && echo yes || echo no)" "yes"
check "the policy file allows 1.0.3" \
  "$(jq -r '.versions | index("1.0.3") != null' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "true"
check "the policy file ships untrusted" \
  "$(jq -r '[.trust.calibration, .trust.smoke] | join(",")' "$P/reference/codex-plugin.json" 2>/dev/null | tr -d '\r')" "pending,pending"

install_plugin 1.0.3 1.0.3
printf 'export class CodexAppServerClient {}\n' > "$PLUG/scripts/lib/app-server.mjs"
enable absent; locate
check "a plugin not named in enabledPlugins is off" "$out" "codex-plugin off reason=plugin-not-enabled"
check "off exits 1" "$rc" "1"
enable false; locate
check "a disabled plugin is off" "$out" "codex-plugin off reason=plugin-not-enabled"
enable true; locate
check "an enabled, installed, allowed plugin is ok" "$out" "codex-plugin ok version=1.0.3 root=$PLUG"
check "ok exits 0" "$rc" "0"
rm "$CFG/plugins/installed_plugins.json"; locate
check "a plugin missing from the registry is not installed" "$out" "codex-plugin off reason=plugin-not-installed"
install_plugin 1.0.3 1.0.2; locate
check "a manifest that disagrees with the registry is missing" "$out" "codex-plugin off reason=plugin-missing"
install_plugin 1.0.4 1.0.4; locate
check "a version outside the allowlist is off" "$out" "codex-plugin off reason=plugin-version:1.0.4"
install_plugin 1.0.3 1.0.3
mv "$PLUG/scripts/lib/app-server.mjs" "$TMP/app-server.mjs"; locate
check "an install without the client library is missing" "$out" "codex-plugin off reason=plugin-missing"
mv "$TMP/app-server.mjs" "$PLUG/scripts/lib/app-server.mjs"
out=$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR= bash "$P/scripts/codex-plugin" extra 2>/dev/null); rc=$?
check "an argument is a usage error" "$rc" "2"

# Registry format 2: several installs per plugin; the user-scope one is used.
printf '{"version":2,"plugins":{"codex@openai-codex":[{"scope":"project","installPath":"%s","version":"9.9.9"},{"scope":"user","installPath":"%s","version":"1.0.3"}]}}\n' \
  "$TMP/elsewhere" "$PLUG" > "$CFG/plugins/installed_plugins.json"
locate
check "the user-scope install is chosen over a project one" "$out" "codex-plugin ok version=1.0.3 root=$PLUG"
install_plugin 1.0.3 1.0.3

# Project settings are read only through CLAUDE_PROJECT_DIR, and local wins.
mkdir -p "$TMP/project/.claude"
printf '{"enabledPlugins":{"codex@openai-codex":false}}\n' > "$TMP/project/.claude/settings.local.json"
out=$(cd "$TMP/work" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$TMP/project" bash "$P/scripts/codex-plugin" 2>/dev/null)
check "project-local settings override the user setting" "$out" "codex-plugin off reason=plugin-not-enabled"
rm -rf "$TMP/project"

# --- the gate ----------------------------------------------------------------
# The stub client's behaviour is chosen per case by GATE_STUB_MODE; it records
# the connect options so direct mode is asserted, and every close() call.
cat > "$PLUG/scripts/lib/app-server.mjs" <<'STUB'
import fs from "node:fs";
const mode = process.env.GATE_STUB_MODE;
const log = (line) => fs.appendFileSync(process.env.GATE_STUB_LOG, `${line}\n`);
export class CodexAppServerClient {
  static async connect(cwd, options) {
    log(`connect disableBroker=${options?.disableBroker === true}`);
    if (mode === "connect-throws") throw new Error("spawn failed");
    if (mode === "hang") await new Promise(() => setInterval(() => {}, 1000));
    return new CodexAppServerClient();
  }
  async request(method) {
    log(`request ${method}`);
    if (method === "account/read") {
      if (mode === "logged-out") return { account: null, requiresOpenaiAuth: true };
      return { account: { type: "chatgpt", email: "a@b.c" }, requiresOpenaiAuth: true };
    }
    if (method === "account/rateLimits/read") {
      if (mode === "method-missing") throw new Error("unknown variant `account/rateLimits/read`");
      if (mode === "rpc-error") throw new Error("internal error");
      if (mode === "shapeless") return { rateLimits: {} };
      if (mode === "quota") return { ordinaryUsageAllowed: false, rateLimits: { primary: { usedPercent: 100, resetsAt: 1789898607 } } };
      if (mode === "full") return { ordinaryUsageAllowed: true, rateLimits: { primary: { usedPercent: 100, resetsAt: 1789898607 } } };
      return { ordinaryUsageAllowed: true, rateLimits: { primary: { usedPercent: 12, resetsAt: 1789898607 } } };
    }
    throw new Error(`unexpected ${method}`);
  }
  async close() { log("close"); }
}
STUB

SESS="$TMP/sessions"
# The trust cases edit a copy: the shipped policy must never change under a
# test, even one that dies halfway. The copy starts untrusted whatever the
# shipped file records, so a gate that passes later changes no case below.
POLICY="$TMP/policy.json"
jq '.trust = {"calibration":"pending","smoke":"pending"}' "$P/reference/codex-plugin.json" > "$POLICY"
gate() { # gate <mode> [args...]; sets out and rc
  local mode="$1"; shift
  out=$(cd "$TMP/work" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR= DR_CODEX_SESSION_DIR="$SESS" DR_CODEX_POLICY="$POLICY" \
    CLAUDE_CODE_SESSION_ID="${SID-s1}" GATE_STUB_MODE="$mode" GATE_STUB_LOG="$TMP/log" \
    DR_CODEX_GATE_TIMEOUT_MS="${GATE_MS:-20000}" bash "$P/scripts/codex-gate" "$@" 2>"$TMP/err"); rc=$?
}
field() { jq -r ".$1 | tostring" "$SESS/s1.json" 2>/dev/null | tr -d '\r'; }
fresh() { rm -rf "$SESS" "$TMP/log"; }

check "codex-gate exists" "$([ -f "$P/scripts/codex-gate" ] && echo yes || echo no)" "yes"

fresh; gate usable
check "a usable but untrusted plugin opens no surface" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
check "the gate exits 0 when it answers" "$rc" "0"
check "the probe connects in direct mode" "$(grep -c 'connect disableBroker=true' "$TMP/log")" "1"
check "the probe reads the login, then the limits" \
  "$(grep '^request' "$TMP/log" | tr '\n' ' ')" "request account/read request account/rateLimits/read "
check "the probe closes its client" "$(grep -c '^close$' "$TMP/log")" "1"
check "the session file records the session" "$(field session_id)" "s1"
check "the session file records the plugin version" "$(field plugin_version)" "1.0.3"
gate usable
check "a second call answers from the cache" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=cache"
check "a cached answer starts no client" "$(grep -c connect "$TMP/log")" "1"

# Trust is read on every call, cache or probe: flipping it must not wait for a
# new session.
cp "$POLICY" "$TMP/policy.bak"
jq '.trust = {"calibration":"pass","smoke":"pass"}' "$TMP/policy.bak" > "$POLICY"
gate usable
check "both gates passed opens both surfaces" "$out" \
  "codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache"
jq '.trust = {"calibration":"pass","smoke":"pending"}' "$TMP/policy.bak" > "$POLICY"
gate usable
check "calibration alone opens only the review seats" "$out" \
  "codex-gate usable=true reason=ok review=true lane=false resets_at=- source=cache"
check "the rewritten file carries the review surface" "$(field review)/$(field lane)" "true/false"
jq '.trust = {"calibration":"pending","smoke":"pass"}' "$TMP/policy.bak" > "$POLICY"
gate usable
check "the smoke test alone opens only the lane" "$out" \
  "codex-gate usable=true reason=ok review=false lane=true resets_at=- source=cache"
jq '.trust = {"calibration":"pass","smoke":"pass"}' "$TMP/policy.bak" > "$POLICY"
fresh; gate quota
check "trust never opens a surface on an unusable Codex" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"
cp "$TMP/policy.bak" "$POLICY"

fresh; gate quota
check "an exhausted quota is off with its reset time" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"
fresh; gate full
check "usage at 100 percent is quota even when ordinary usage is allowed" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"
fresh; gate logged-out
check "a logged-out plugin is off" "$out" \
  "codex-gate usable=false reason=logged-out review=false lane=false resets_at=- source=probe"
fresh; gate method-missing
check "an app-server without the limits method is off" "$out" \
  "codex-gate usable=false reason=method-missing review=false lane=false resets_at=- source=probe"
fresh; gate rpc-error
check "any other limits error is off" "$out" \
  "codex-gate usable=false reason=plugin-api review=false lane=false resets_at=- source=probe"
fresh; gate shapeless
check "a limits reply without the signal is off" "$out" \
  "codex-gate usable=false reason=plugin-api review=false lane=false resets_at=- source=probe"
fresh; gate connect-throws
check "a connect that throws is off" "$out" \
  "codex-gate usable=false reason=plugin-api review=false lane=false resets_at=- source=probe"
fresh; GATE_MS=1500 gate hang
check "a hung connect times out" "$out" \
  "codex-gate usable=false reason=timeout review=false lane=false resets_at=- source=probe"

# The quota answer is cached only until its reset time.
fresh; gate quota
jq '.resets_at_epoch = 1577836800' "$SESS/s1.json" > "$TMP/s.json" && mv "$TMP/s.json" "$SESS/s1.json"
gate usable
check "a quota past its reset time is probed again" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
gate quota --refresh
check "--refresh probes even with a cached answer" "$out" \
  "codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=probe"

# Another session's file is never this session's answer.
fresh; gate quota
SID=s2 gate usable
check "a different session probes for itself" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"

# Without a session id nothing can be cached or read back, so nothing is written.
fresh; SID= gate usable
check "no session id still answers" "$out" \
  "codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
check "no session id writes no file" "$(ls "$SESS" 2>/dev/null | wc -l | tr -d ' ')" "0"

fresh; enable false; gate usable
check "a disabled plugin never starts a client" "$out" \
  "codex-gate usable=false reason=plugin-not-enabled review=false lane=false resets_at=- source=probe"
check "a disabled plugin writes no client log" "$([ -f "$TMP/log" ] && echo yes || echo no)" "no"
enable true

gate usable --bogus
check "an unknown flag is a usage error" "$rc" "2"

# --- the session readers -----------------------------------------------------
. "$P/scripts/lib/codex-session.sh"
export DR_CODEX_SESSION_DIR="$SESS" CLAUDE_CODE_SESSION_ID=s1
on() { # on <name> <surface> <want: on|off>
  if codex_session_on "$2"; then check "$1" on "$3"; else check "$1" off "$3"; fi
}
fresh; mkdir -p "$SESS"
on "no file is off" review off
printf '{"session_id":"s1","usable":true,"review":true,"lane":false}\n' > "$SESS/s1.json"
on "an open review surface is on" review on
on "a closed lane is off" lane off
codex_session_mark_off quota
check "mark_off closes both surfaces" "$(field usable)/$(field review)/$(field lane)/$(field reason)" "false/false/false/quota"
on "a marked-off session is off" review off
printf 'not json' > "$SESS/s1.json"
on "a torn file is off" review off
CLAUDE_CODE_SESSION_ID=""
printf '{"session_id":"","usable":true,"review":true,"lane":true}\n' > "$SESS/.json"
on "no session id is off whatever is on disk" review off

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
