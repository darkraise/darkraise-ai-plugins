#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
export DCC_FAKE_HOME="$fake" DCC_CACHE_HOME="$fake/cache"
export HOME="$fake"
export DCC_WT_SETTINGS="$HERE/fixtures/wt-plain.json"
unset DCC_STATUSLINE_HOME CLAUDE_CONFIG_DIR
mkdir -p "$fake/.claude" "$fake/.claude-alt"
printf '{"unrelated":42}\n' > "$fake/.claude/settings.json"
printf '{}\n' > "$fake/.claude-alt/settings.json"
printf '{"oauthAccount":{"emailAddress":"main@example.com"}}\n' > "$fake/.claude.json"
printf '{"oauthAccount":{"emailAddress":"alt@example.com"}}\n' > "$fake/.claude-alt/.claude.json"
install_script="$HERE/../scripts/install.sh"
registry="$fake/.claude/dcc-statusline-installations.json"
custom="$fake/custom scripts' dollar\$"
export DCC_STATUSLINE_HOME="$custom"
bash "$install_script" install >/dev/null 2>&1
check 'custom destination recorded' "$(MSYS2_ARG_CONV_EXCL='*' jq -r --arg a "$fake/.claude" '.accounts[$a].destination' < "$registry" 2>/dev/null)" "$custom"
command_text="$(jq -r '.statusLine.command' "$fake/.claude/settings.json")"
rendered="$(printf '{"model":{"display_name":"ownership-probe"}}' | bash -c "$command_text" 2>/dev/null)"
check 'quoted installed command runs renderer' "$([[ "$rendered" == *ownership-probe* ]] && echo yes || echo no)" yes
unset DCC_STATUSLINE_HOME
printf '0.7.0\n' > "$custom/VERSION"
CLAUDE_PLUGIN_ROOT="$HERE/.." bash "$HERE/../scripts/sync.sh" >/dev/null 2>&1
check 'sync resolves record without override' "$(cat "$custom/VERSION")" "$(cat "$HERE/../scripts/VERSION")"
out="$(DCC_STATUSLINE_HOME="$fake/wrong" bash "$install_script" status)"
check 'status ignores changed ambient destination' "$([[ "$out" == *"$custom"* ]] && echo yes || echo no)" yes
out="$(bash "$install_script" doctor 2>&1)"
check 'doctor finds recorded destination' "$([[ "$out" == *"scripts are installed at $custom"* ]] && echo yes || echo no)" yes
bash "$install_script" uninstall >/dev/null 2>&1
check 'custom uninstall removes owned command' "$(jq -r 'has("statusLine")' "$fake/.claude/settings.json")" false
check 'uninstall removes record' "$(MSYS2_ARG_CONV_EXCL='*' jq -r --arg a "$fake/.claude" '.accounts | has($a)' < "$registry" 2>/dev/null)" false
check 'uninstall retains script directory' "$([ -d "$custom" ] && echo yes || echo no)" yes
printf '{"statusLine":{"type":"command","command":"other-provider"},"unrelated":42}\n' > "$fake/.claude/settings.json"
before="$(cat "$fake/.claude/settings.json")"
bash "$install_script" uninstall >/dev/null 2>&1
check 'uninstall preserves another provider' "$(cat "$fake/.claude/settings.json")" "$before"
out="$(bash "$install_script" status)"
check 'status identifies another provider' "$([[ "$out" == *'another provider'* ]] && echo yes || echo no)" yes
printf '{bad json\n' > "$fake/.claude/settings.json"
bash "$install_script" install >/dev/null 2>&1
check 'malformed settings install fails' "$?" 1
check 'malformed settings unchanged' "$(cat "$fake/.claude/settings.json")" '{bad json'
printf '{}\n' > "$fake/.claude/settings.json"
printf '{broken registry\n' > "$registry"
bash "$install_script" install >/dev/null 2>&1
check 'malformed registry install fails' "$?" 1
check 'malformed registry preserved' "$(cat "$registry")" '{broken registry'
rm -f "$registry"
printf '{"statusLine":{"type":"command","command":"bash ~/.claude/dcc-statusline/statusline.sh"}}\n' > "$fake/.claude/settings.json"
bash "$install_script" uninstall >/dev/null 2>&1
check 'legacy default command can be removed' "$(jq -r 'has("statusLine")' "$fake/.claude/settings.json")" false
printf '{broken\n' > "$fake/.claude-alt/settings.json"
bash "$install_script" install --all > "$fake/all.log" 2>&1
check 'all accounts aggregate errors' "$?" 1
check 'all accounts report success and failure' "$(wc -l < "$fake/all.log" | tr -d ' ')" 2
printf '{}\n' > "$fake/.claude-alt/settings.json"
source "$HERE/../scripts/install.sh"
DCC_STATUSLINE_HOME="$fake/destination one" dcc_install_one "$fake/.claude" >/dev/null
DCC_STATUSLINE_HOME="$fake/destination two" dcc_install_one "$fake/.claude-alt" >/dev/null
bash "$install_script" install --all >/dev/null 2>&1
check 'all preserves first account destination' "$(MSYS2_ARG_CONV_EXCL='*' jq -r --arg a "$fake/.claude" '.accounts[$a].destination' < "$registry")" "$fake/destination one"
check 'all preserves second account destination' "$(MSYS2_ARG_CONV_EXCL='*' jq -r --arg a "$fake/.claude-alt" '.accounts[$a].destination' < "$registry")" "$fake/destination two"
printf '0.7.0\n' > "$fake/destination one/VERSION"
jq '.statusLine.command="other-provider"' "$fake/.claude/settings.json" > "$fake/other.json"
mv "$fake/other.json" "$fake/.claude/settings.json"
CLAUDE_PLUGIN_ROOT="$HERE/.." bash "$HERE/../scripts/sync.sh" >/dev/null 2>&1
check 'sync cannot activate a mismatched installation' "$(cat "$fake/destination one/VERSION")" '0.7.0'
bash "$install_script" install >/dev/null 2>&1
check 'explicit reinstall repairs a mismatch' "$(jq -r '.statusLine.command' "$fake/.claude/settings.json")" "bash $fake/destination\\ one/statusline.sh"
bash "$HERE/../scripts/manage.sh" preview --width 80 > "$fake/preview.log" 2>&1
check 'dispatcher consumes preview subcommand once' "$?" 0
bash "$HERE/../scripts/manage.sh" install --all > "$fake/manage.log" 2>&1
check 'dispatcher consumes install subcommand once' "$?" 0
check 'dispatcher reaches both accounts' "$(wc -l < "$fake/manage.log" | tr -d ' ')" 2
mkdir "$registry.lock"
bash "$install_script" install >/dev/null 2>&1
check 'contended installer fails within bounded lock wait' "$?" 1
rmdir "$registry.lock"
mkdir "$registry.lock"; printf '%s\n' "$$" > "$registry.lock/pid"
bash "$install_script" install >/dev/null 2>&1
check 'a live owner still blocks the installer' "$?" 1
rm -rf "$registry.lock"
sleep 0 & dead=$!; wait "$dead"
mkdir "$registry.lock"; printf '%s\n' "$dead" > "$registry.lock/pid"
bash "$install_script" install >/dev/null 2>&1
check 'a dead owner lock is broken' "$?" 0
check 'the broken lock is released after install' "$([ -e "$registry.lock" ] && echo held || echo free)" free
mkdir "$registry.lock"; touch -t 200001010000 "$registry.lock"
bash "$install_script" install >/dev/null 2>&1
check 'an old ownerless lock is broken' "$?" 0
rm -rf "$registry.lock"

# Two waiters break one stale lock. The rm hook lets the second act after the
# first has passed its checks; it must not end up holding a lock the first
# then removes.
race="$fake/race.lock"
sleep 0 & dead=$!; wait "$dead"
mkdir "$race"; printf '%s\n' "$dead" > "$race/pid"
(
  source "$HERE/../scripts/lib/installations.sh"
  first=1
  rm() {
    if [ "$first" = 1 ]; then
      first=0
      if _dcc_installation_break_stale "$race" && mkdir "$race" 2>/dev/null; then
        printf '%s\n' "$$" > "$race/pid"; : > "$fake/second-took"
      fi
    fi
    command rm "$@"
  }
  _dcc_installation_break_stale "$race"
)
check 'the first waiter breaks the stale lock' "$?" 0
took=$([ -e "$fake/second-took" ] && echo yes || echo no)
held=$([ -f "$race/pid" ] && echo yes || echo no)
check 'a lock the second waiter took is still held' "took=$took held=$held" "took=$took held=$took"
command rm -rf "$race" "$fake/second-took"

mkdir "$registry.lock.break"; touch -t 200001010000 "$registry.lock.break"
sleep 0 & dead=$!; wait "$dead"
mkdir "$registry.lock"; printf '%s\n' "$dead" > "$registry.lock/pid"
bash "$install_script" install >/dev/null 2>&1
check 'an abandoned breaker guard does not block breaking a stale lock' "$?" 0
check 'the abandoned guard is cleared' "$([ -e "$registry.lock.break" ] && echo present || echo gone)" gone
rm -rf "$registry.lock" "$registry.lock.break"
finish
