#!/usr/bin/env bash
# Emits a JSON roster of external agent CLIs. Read at plan time to populate the
# executor checkbox, and again at dispatch as a guard, because a roster can go
# stale between the two.
#
# batch_capable is a static fact about a tool, not a probe result: it records
# whether the CLI can run a task headlessly and return a result a script can
# read. Antigravity fails that test on its interface, not on its installation.
#
# `usable` means dispatchable, which is what both skills read it as, so it also
# requires that this plugin ships a lane for the CLI. A batch-capable tool with
# no wrapper would otherwise be offered at plan time, tick into the plan header,
# and then have nothing to run it - a deadlock no failure-mode row covers.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/native-path.sh"

# Every field this script emits is built with jq. Without it the script would
# exit 127 with empty stdout, which the dispatching skill reads as "no executor
# usable" - a silent downgrade of the whole lane.
command -v jq >/dev/null 2>&1 || {
  printf 'detect-executors: jq is required but not on PATH
' >&2
  exit 2
}
command -v timeout >/dev/null 2>&1 || {
  printf 'detect-executors: GNU timeout is required but not on PATH\n' >&2
  exit 2
}

emit() { # emit <id> <batch_capable> <incapable_reason>
  local id="$1" capable="$2" incapable_reason="$3"
  local path present version authed reason usable auth_status=not_applicable
  local registered=no

  # A registry id is reached only through its own locator and probe: presence,
  # version and login state come from them, never from a PATH probe. Every
  # other id keeps the PATH probe, because no registry entry owns it.
  if bash "$HERE/executors" get "$id" id >/dev/null 2>&1; then
    registered=yes
    path=""
    present=false
    version=null
    authed=null
    auth_status=not_applicable
    local locator probe_cmd probe_op locator_line locator_root auth_json
    locator=$(bash "$HERE/executors" path "$id" locator 2>/dev/null)
    probe_cmd=$(bash "$HERE/executors" path "$id" probe.command 2>/dev/null)
    probe_op=$(bash "$HERE/executors" get "$id" probe.op 2>/dev/null)
    if [ -n "$locator" ] && locator_line=$(bash "$locator" 2>/dev/null); then
      present=true
      locator_root=${locator_line#*root=}
      path=$locator_root
      version=$(jq -Rn --arg v "${locator_line#*version=}" '$v | sub(" root=.*"; "")')
      auth_json=$(printf '{"op":"%s","cwd":"%s"}' "$probe_op" "$(dr_native_path "$PWD")" \
        | timeout 60 node "$probe_cmd" "$locator_root" 2>/dev/null)
      case "$(jq -r '.authed | tojson' <<<"${auth_json:-{\}}" 2>/dev/null)" in
        true)  authed=true;  auth_status=authenticated ;;
        false) authed=false; auth_status=logged_out ;;
        *)     authed=null;  auth_status=probe_failed ;;
      esac
    fi
  else
    path=$(command -v "$id" 2>/dev/null || true)
    if [ -n "$path" ]; then present=true; else present=false; fi
    version=null
    if [ "$present" = true ]; then
      local v
      v=$(timeout 20 "$id" --version 2>/dev/null | head -1 | tr -d '\r')
      [ -n "$v" ] && version=$(jq -Rn --arg v "$v" '$v')
    fi
    authed=null
  fi

  usable=false
  reason=null
  # A `reasons.*` key is optional, so an entry that declares none must still
  # produce a message: an empty reason would emit `usable:false reason:""`,
  # which reads as neither a cause nor an absent field.
  entry_reason() {
    local r; r=$(bash "$HERE/executors" get "$id" "reasons.$1" 2>/dev/null)
    [ -n "$r" ] || r="$id is not usable ($1); its registry entry declares no reasons.$1 message"
    printf '%s' "$r"
  }
  if [ "$present" != true ]; then
    if [ "$registered" = yes ]; then
      reason=$(jq -Rn --arg r "$(entry_reason not_enabled)" '$r')
    else
      reason='"not on PATH"'
    fi
  elif [ "$capable" != true ]; then
    reason=$(jq -Rn --arg r "$incapable_reason" '$r')
  elif [ "$registered" != yes ]; then
    reason=$(jq -Rn --arg r "no executor lane is implemented for $id in this plugin; run 'executors list' for the registered executors" '$r')
  elif [ ! -r "$(bash "$HERE/executors" path "$id" wrapper 2>/dev/null)" ]; then
    # Registered but broken: an installation fault rather than an executor
    # state, so the message is generated rather than taken from the map.
    reason=$(jq -Rn --arg r "the $id executor is registered but its wrapper is missing" '$r')
  elif [ "$authed" = false ]; then
    reason=$(jq -Rn --arg r "$(entry_reason logged_out)" '$r')
  elif [ "$auth_status" = probe_failed ]; then
    reason=$(jq -Rn --arg r "$(entry_reason probe_failed)" '$r')
  elif [ "$version" = null ] && [ "$registered" != yes ]; then
    reason='"version probe failed; check the CLI installation"'
  else
    usable=true
  fi

  jq -n \
    --arg id "$id" \
    --argjson present "$present" \
    --argjson version "$version" \
    --argjson authed "$authed" \
    --arg auth_status "$auth_status" \
    --argjson batch_capable "$capable" \
    --argjson usable "$usable" \
    --argjson reason "$reason" \
    --arg path "$path" \
    '{id:$id, present:$present, path:(if $path=="" then null else $path end),
      version:$version, authed:$authed, auth_status:$auth_status, batch_capable:$batch_capable,
      usable:$usable, reason:$reason}'
}

{
  registered=$(bash "$HERE/executors" list 2>/dev/null)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    emit "$id" true ""
  done <<<"$registered"

  # Ids with no registry entry. Each is skipped when registered, so a second
  # executor never produces two rows under one id.
  path_row() { grep -qxF "$1" <<<"$registered" || emit "$1" "$2" "$3"; }
  path_row cursor-agent true ""
  path_row opencode true ""
  path_row antigravity false "installed, but its only agent mode (antigravity chat -m agent) opens a GUI editor session with no output file, no completion signal, and no exit code tied to the work"
} | jq -s '.'
