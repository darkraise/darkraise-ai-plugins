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
