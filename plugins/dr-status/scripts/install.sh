#!/usr/bin/env bash
# Installs the statusLine entry into a Claude account's settings.json. A plugin
# cannot register a statusLine itself -- plugin settings.json supports only the
# agent and subagentStatusLine keys -- so the entry has to live in user settings.
#
# The command written points at a stable copy outside the versioned plugin cache,
# because ${CLAUDE_PLUGIN_ROOT} changes on every plugin update.
set -uo pipefail

DCC_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCC_COMMAND="bash ~/.claude/dcc-statusline/statusline.sh"
# Terminal resize is not one of Claude Code's status line update triggers, so a
# resized terminal keeps its old layout until the next run. The refresh timer is
# the only thing that bounds that lag. Doctor compares against this same value,
# so the writer and the checker cannot drift apart.
DCC_REFRESH=2

# dcc_doctor resolves the active account key exactly the way the render path
# does, so a mismatch between the two can never be what the diagnostic misses.
source "$DCC_SRC_DIR/lib/path.sh"
source "$DCC_SRC_DIR/lib/installations.sh"
source "$DCC_SRC_DIR/lib/jq-prog.sh"
source "$DCC_SRC_DIR/lib/config.sh"
source "$DCC_SRC_DIR/lib/validate.sh"

_dcc_paths() { # -> DCC_HOME_DIR, DCC_DEST -- resolved fresh on every call, never
               # cached at source time, because a caller (tests, in particular)
               # may set DCC_FAKE_HOME / DCC_STATUSLINE_HOME after sourcing this
               # file rather than before it
  DCC_HOME_DIR="${DCC_FAKE_HOME:-$HOME}"
  DCC_DEST="${DCC_STATUSLINE_HOME:-$DCC_HOME_DIR/.claude/dcc-statusline}"
}

dcc_account_dirs() { # prints each qualifying account config dir, one per line
  _dcc_paths
  local d j
  for d in "$DCC_HOME_DIR"/.claude "$DCC_HOME_DIR"/.claude-*; do
    [ -d "$d" ] || continue
    [ -f "$d/settings.json" ] || continue
    if [ "$d" = "$DCC_HOME_DIR/.claude" ]; then j="$DCC_HOME_DIR/.claude.json"; else j="$d/.claude.json"; fi
    [ -f "$j" ] || continue
    jq -e '.oauthAccount.emailAddress // empty' "$j" >/dev/null 2>&1 || continue
    printf '%s\n' "$d"
  done
}

dcc_copy_scripts() {
  _dcc_paths
  [ -z "${1:-}" ] || DCC_DEST="$1"
  mkdir -p "$DCC_DEST" || return 1
  cp -R "$DCC_SRC_DIR/." "$DCC_DEST/" 2>/dev/null || return 1
  # install.sh and sync.sh are plugin-side entry points; the copy only needs the
  # render path, but copying everything keeps VERSION comparison trivial.
  # The probe forks freely; it runs here rather than in the render path, which
  # budgets five processes and cannot afford to look at fonts.
  bash "$DCC_DEST/detect-font.sh" "$DCC_DEST/icons.detected" >/dev/null 2>&1 || true
  return 0
}

_dcc_edit_settings() { # _dcc_edit_settings <dir> <jq-program>
  local dir="$1" prog="$2" tmp
  shift 2
  local settings="$dir/settings.json"
  mkdir -p -- "$dir" || return 1
  tmp="$(mktemp "$settings.XXXXXX")" || return 1
  local input='{}'
  if [ -e "$settings" ]; then input="$(cat "$settings")" || { rm -f -- "$tmp"; return 1; }; fi
  if jq -e --indent 2 "$@" "select(type == \"object\") | $prog" <<< "$input" > "$tmp" 2>/dev/null && mv -f -- "$tmp" "$settings"; then return 0; fi
  rm -f -- "$tmp"
  return 1
}

dcc_install_one() { # dcc_install_one <config-dir>
  dcc_installation_lock || return 1
  local result=0
  _dcc_install_one "$1" || result=1
  dcc_installation_unlock || result=1
  return "$result"
}

_dcc_install_one() {
  local destination command
  dcc_installation_resolve "$1" install || return 1
  destination="$DCC_DEST"; command="$DCC_COMMAND"
  if [ -e "$1/settings.json" ]; then jq -e 'type == "object"' "$1/settings.json" >/dev/null 2>&1 || return 1; fi
  dcc_copy_scripts "$destination" || return 1
  dcc_seed_config || return 1
  dcc_installation_put "$1" "$destination" "$command" || return 1
  _dcc_edit_settings "$1" '.statusLine = {type:"command", command:$command, padding:0, refreshInterval:$refresh}' \
    --arg command "$command" --argjson refresh "$DCC_REFRESH"
}

dcc_uninstall_one() { # dcc_uninstall_one <config-dir>
  dcc_installation_lock || return 1
  local result=0
  if ! dcc_installation_read >/dev/null; then result=1
  elif [ -e "$1/settings.json" ] && ! jq -e 'type == "object"' "$1/settings.json" >/dev/null 2>&1; then result=1
  elif dcc_installation_owns "$1"; then
    _dcc_edit_settings "$1" 'del(.statusLine)' && dcc_installation_remove "$1" || result=1
  fi
  dcc_installation_unlock || result=1
  return "$result"
}

dcc_seed_config() { # seeds only what is genuinely per-machine -- everything
  # presentational (lines, glyphs, meters, ...) already has a default in
  # lib/config.sh and must keep tracking it, never fork into a stale copy here.
  _dcc_paths
  local cfg="$DCC_HOME_DIR/.claude/dcc-statusline.json"
  [ -f "$cfg" ] && return 0
  mkdir -p "$DCC_HOME_DIR/.claude" || return 0
  cat > "$cfg" <<'JSON'
{
  "$schema": "./dcc-statusline/dcc-statusline.schema.json",
  "accounts": {}
}
JSON
}

dcc_targets() { # dcc_targets <--all|"">
  _dcc_paths
  if [ "${1:-}" = "--all" ]; then
    local records
    records="$(dcc_installation_read)" || return 1
    { dcc_account_dirs; dcc_installation_json -r '.accounts | keys[]' <<< "$records"; } | sort -u
  elif [ -n "${DCC_FAKE_HOME:-}" ]; then
    # DCC_FAKE_HOME is a test-only isolation switch. Once set, it must be
    # authoritative: an ambient CLAUDE_CONFIG_DIR from the caller's real shell
    # (routine for anyone running a non-default account) must not be able to
    # redirect an isolated run onto a real account.
    printf '%s\n' "$DCC_HOME_DIR/.claude"
  else
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$DCC_HOME_DIR/.claude}"
  fi
}

dcc_doctor() {
  _dcc_paths
  local active
  active="$(dcc_targets)" || return 1
  dcc_installation_resolve "$active" || { printf 'FAIL - invalid installation registry\n'; return 1; }
  local rc=0 d cfg key probe rendered dcc_m dcc_w iv
  cfg="$DCC_HOME_DIR/.claude/dcc-statusline.json"
  command -v jq  >/dev/null 2>&1 && printf 'ok   - jq is on PATH\n'  || { printf 'FAIL - jq is not on PATH\n';  rc=1; }
  command -v git >/dev/null 2>&1 && printf 'ok   - git is on PATH\n' || { printf 'warn - git is not on PATH; the git segment will be hidden\n'; }
  if [ -f "$DCC_DEST/statusline.sh" ]; then
    printf 'ok   - scripts are installed at %s\n' "$DCC_DEST"
    if cmp -s "$DCC_SRC_DIR/VERSION" "$DCC_DEST/VERSION"; then
      printf 'ok   - installed copy matches the plugin version\n'
    else
      printf 'warn - installed copy is stale; run: /dr-status install\n'
    fi
  else
    printf 'FAIL - scripts are not installed; run: /dr-status install\n'; rc=1
  fi
  if [ -r "$DCC_DEST/icons.detected" ]; then
    read -r dcc_m dcc_w < "$DCC_DEST/icons.detected"
    printf 'icons: %s at %s cell(s)\n' "${dcc_m:-unknown}" "${dcc_w:-?}"
  else
    printf 'icons: not detected yet -- run install to probe\n'
  fi
  if dcc_validate "$cfg"; then :; else rc=1; fi

  # Whether the active account has a matching accounts{} entry. A key that never
  # matches costs the tint and nothing else, so it produces no error anywhere --
  # printing the resolved key is the only way a user finds out.
  dcc_config_key "$DCC_HOME_DIR"; key="$DCC_ACCT_KEY"
  if [ ! -f "$cfg" ]; then
    printf 'warn - no config file, so no tint is defined for %s\n' "$key"
  elif jq -e --arg k "$key" '.accounts[$k].color // empty' "$cfg" >/dev/null 2>&1; then
    printf 'ok   - %s has an accounts entry\n' "$key"
  else
    printf 'warn - %s has no accounts entry; this account renders untinted\n' "$key"
  fi

  # Every check above can pass while the render itself is broken, so run one.
  # Built-in defaults deliberately, since the user config was just checked
  # separately and a config that hides the model segment is not a render fault.
  probe='{"model":{"display_name":"dcc-probe"},"cost":{"total_cost_usd":0}}'
  # Matched with a case statement rather than piping into grep -q: -q closes the
  # pipe on its first match, and under pipefail the resulting SIGPIPE in the
  # renderer would be reported as a failed render.
  rendered="$(printf '%s' "$probe" \
    | DCC_STATUSLINE_CONFIG=/dev/null bash "$DCC_SRC_DIR/statusline.sh" 2>/dev/null)"
  case "$rendered" in
    *dcc-probe*) printf 'ok   - a fixture render succeeds\n' ;;
    *)           printf 'FAIL - a fixture render produced no usable output\n'; rc=1 ;;
  esac

  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if dcc_installation_owns "$d"; then
      if [ -f "$DCC_DEST/statusline.sh" ]; then printf 'ok   - installed in %s\n' "$d"
      else printf 'FAIL - registered in %s but scripts are missing at %s\n' "$d" "$DCC_DEST"; rc=1; fi
      cmp -s "$DCC_SRC_DIR/VERSION" "$DCC_DEST/VERSION" || printf 'warn - stale or missing script version for %s\n' "$d"
      iv="$(jq -r '.statusLine.refreshInterval // "unset"' "$d/settings.json" 2>/dev/null)"
      if [ "$iv" != "$DCC_REFRESH" ]; then
        printf 'warn - %s has refreshInterval %s; a resize will lag. Run: /dr-status install\n' \
          "$d" "$iv"
      fi
    else
      printf 'warn - not installed or another provider/record mismatch in %s\n' "$d"
    fi
  done < <(dcc_targets --all)
  return "$rc"
}

dcc_status() {
  _dcc_paths
  local d targets
  targets="$(dcc_targets --all)" || { printf 'invalid installation registry\n' >&2; return 1; }
  # Read line by line: a home directory containing a space would word-split an
  # unquoted command substitution into fragments that name no directory.
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if dcc_installation_owns "$d"; then
      if [ -f "$DCC_DEST/statusline.sh" ]; then printf '%s: installed at %s\n' "$d" "$DCC_DEST"
      else printf '%s: registered; scripts missing at %s\n' "$d" "$DCC_DEST"; fi
      [ ! -f "$DCC_DEST/VERSION" ] || printf 'installed script version: %s\n' "$(cat "$DCC_DEST/VERSION")"
    else
      printf '%s: not installed or another provider/record mismatch\n' "$d"
    fi
  done <<< "$targets"
  printf 'plugin script version: %s\n' "$(cat "$DCC_SRC_DIR/VERSION")"
}

dcc_main() {
  _dcc_paths
  local action="${1:-status}" targets d result=0 owned
  [ "$#" -eq 0 ] || shift
  [ "$#" -le 1 ] && { [ "$#" -eq 0 ] || [ "$1" = --all ]; } || { printf 'invalid arguments\n' >&2; return 2; }
  command -v jq >/dev/null 2>&1 && command -v realpath >/dev/null 2>&1 || { printf 'jq and GNU realpath are required\n' >&2; return 2; }
  case "$action" in
    install|uninstall)
      targets="$(dcc_targets "${1:-}")" || return 1
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        owned=yes
        if [ "$action" = uninstall ] && ! dcc_installation_owns "$d"; then owned=no; fi
        if "dcc_${action}_one" "$d"; then
          if [ "$owned" = yes ]; then printf '%sed: %s\n' "$action" "$d"
          else printf 'unchanged: %s (not installed, another provider, or record mismatch)\n' "$d"; fi
        else printf 'failed: %s\n' "$d"; result=1; fi
      done <<< "$targets"
      return "$result"
      ;;
    status) dcc_status ;;
    doctor) dcc_doctor ;;
    *) printf 'usage: install.sh {install|uninstall|status|doctor} [--all]\n'; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then dcc_main "$@"; fi
