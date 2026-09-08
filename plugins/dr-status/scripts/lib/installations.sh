#!/usr/bin/env bash

# Native Windows jq otherwise rewrites MSYS path values passed through --arg.
# File input uses shell redirection so only JSON data crosses the argv boundary.
dcc_installation_json() { MSYS2_ARG_CONV_EXCL='*' jq "$@" | tr -d '\r'; }

dcc_installation_path() {
  DCC_HOME_DIR="${DCC_FAKE_HOME:-$HOME}"
  DCC_REGISTRY="$DCC_HOME_DIR/.claude/dcc-statusline-installations.json"
}

dcc_installation_absolute() {
  dcc_path_norm "$1"
  realpath -m -- "$DCC_PATH"
}

dcc_installation_read() {
  dcc_installation_path
  if [ ! -e "$DCC_REGISTRY" ]; then printf '{"version":1,"accounts":{}}\n'; return; fi
  dcc_installation_json -e 'def absolute: test("^(/|[A-Za-z]:[/\\\\])");
    select(type == "object" and .version == 1 and (.accounts | type == "object")) |
    select(all(.accounts | keys[]; absolute)) |
    select(all(.accounts[]; type == "object" and (.destination | type == "string") and
      (.command | type == "string") and (.destination | absolute) and (.command | length > 0)))' \
    < "$DCC_REGISTRY" 2>/dev/null
}

dcc_installation_get() {
  local account record
  account="$(dcc_installation_absolute "$1")" || return 1
  record="$(dcc_installation_read)" || return 1
  dcc_installation_json -c --arg account "$account" '.accounts[$account] // null' <<< "$record"
}

dcc_installation_save() {
  local record="$1" tmp
  dcc_installation_path
  tmp="$(mktemp "$DCC_REGISTRY.XXXXXX")" || return 1
  if printf '%s\n' "$record" > "$tmp" && dcc_installation_json -e . < "$tmp" >/dev/null && mv -f -- "$tmp" "$DCC_REGISTRY"; then return 0; fi
  rm -f -- "$tmp"
  return 1
}

dcc_installation_put() {
  local account record
  account="$(dcc_installation_absolute "$1")" || return 1
  record="$(dcc_installation_read)" || return 1
  record="$(dcc_installation_json --arg account "$account" --arg destination "$2" --arg command "$3" \
    '.accounts[$account] = {destination:$destination, command:$command}' <<< "$record")" || return 1
  dcc_installation_save "$record"
}

dcc_installation_remove() {
  local account record
  account="$(dcc_installation_absolute "$1")" || return 1
  record="$(dcc_installation_read)" || return 1
  record="$(dcc_installation_json --arg account "$account" 'del(.accounts[$account])' <<< "$record")" || return 1
  dcc_installation_save "$record"
}

dcc_installation_resolve() {
  local account="$1" mode="${2:-read}" record destination
  record="$(dcc_installation_get "$account")" || return 1
  destination="$(dcc_installation_json -r '.destination // empty' <<< "$record")"
  if [ "$mode" = install ] && [ -n "${DCC_STATUSLINE_HOME:-}" ]; then destination="$DCC_STATUSLINE_HOME"; fi
  DCC_DEST="$(dcc_installation_absolute "${destination:-${DCC_FAKE_HOME:-$HOME}/.claude/dcc-statusline}")" || return 1
  if [ "$mode" = install ]; then
    printf -v DCC_COMMAND 'bash %q' "$DCC_DEST/statusline.sh"
  else
    DCC_COMMAND="$(dcc_installation_json -r '.command // "bash ~/.claude/dcc-statusline/statusline.sh"' <<< "$record")"
  fi
}

dcc_installation_owns() {
  local account="$1" actual
  dcc_installation_resolve "$account" || return 1
  actual="$(dcc_installation_json -er 'select(.statusLine.type == "command") | .statusLine.command' < "$account/settings.json" 2>/dev/null)" || return 1
  [ "$actual" = "$DCC_COMMAND" ]
}

dcc_installation_lock() {
  dcc_installation_path
  mkdir -p -- "$(dirname "$DCC_REGISTRY")" || return 1
  local attempts=0 lock="$DCC_REGISTRY.lock"
  while ! mkdir -- "$lock" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 50 ] || return 1
    sleep 0.1
  done
  DCC_INSTALL_LOCK_DIR="$lock"
}

dcc_installation_unlock() {
  [ -n "${DCC_INSTALL_LOCK_DIR:-}" ] || return 0
  rmdir -- "$DCC_INSTALL_LOCK_DIR" || return 1
  DCC_INSTALL_LOCK_DIR=''
}
