#!/usr/bin/env bash
# Emits a JSON roster of the registered external reviewers, one row per id.
# With ids, only those are probed: a review runner asks for its own family, so
# one seat never pays for another family's probe.
#
# Usage: detect-executors.sh [ID ...]
# Exit: 0 answered; 2 an unregistered id, or jq or timeout missing.
#
# `usable` means a review can run, so it also requires the entry's runner to be
# readable: a registered reviewer with no runner would be selected and then
# have nothing to run it.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/native-path.sh"
. "$HERE/lib/timeout.sh"

# Every field this script emits is built with jq. Without it the script would
# exit 127 with empty stdout, which the dispatching skill reads as "no executor
# usable" - a silent downgrade of the whole lane.
command -v jq >/dev/null 2>&1 || {
  printf 'detect-executors: jq is required but not on PATH
' >&2
  exit 2
}
dforge_timeout || {
  printf 'detect-executors: GNU timeout (timeout or gtimeout) is required but not on PATH\n' >&2
  exit 2
}

emit() { # emit <id>
  local id="$1"
  local path present version authed reason usable auth_status=not_applicable
  local locator_reason=

  # A registry id is reached only through its own locator and probe: presence,
  # version and login state come from them, never from a PATH probe.
  path=""
  present=false
  version=null
  authed=null
  auth_status=not_applicable
  local locator probe_cmd probe_op locator_line locator_root auth_json
  locator=$(bash "$HERE/executors" path "$id" locator 2>/dev/null)
  probe_cmd=$(bash "$HERE/executors" path "$id" probe.command 2>/dev/null)
  probe_op=$(bash "$HERE/executors" get "$id" probe.op 2>/dev/null)
  # A locator states why it said no. Dropping that and reporting the first
  # reason in the list sends the reader to fix something that is not broken.
  if [ -n "$locator" ] && ! locator_line=$(bash "$locator" 2>/dev/null); then
    case "$locator_line" in *reason=*) locator_reason=${locator_line#*reason=} ;; esac
  elif [ -n "$locator" ]; then
    present=true
    locator_root=${locator_line#*root=}
    path=$locator_root
    version=$(jq -Rn --arg v "${locator_line#*version=}" '$v | sub(" root=.*"; "")')
    auth_json=$(jq -nc --arg op "$probe_op" --arg cwd "$(dr_native_path "$PWD")" '{op: $op, cwd: $cwd}' \
      | "$DFORGE_TIMEOUT" 60 node "$probe_cmd" "$locator_root" 2>/dev/null)
    case "$(jq -r '.authed | tojson' <<<"${auth_json:-{\}}" 2>/dev/null)" in
      true)  authed=true;  auth_status=authenticated ;;
      false) authed=false; auth_status=logged_out ;;
      *)     authed=null;  auth_status=probe_failed ;;
    esac
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
    case "$locator_reason" in
      plugin-version:*)
        reason=$(jq -Rn --arg r "the $id plugin is version ${locator_reason#plugin-version:}, outside the version range this plugin trusts" '$r') ;;
      plugin-not-installed) reason=$(jq -Rn --arg r "$(entry_reason not_installed)" '$r') ;;
      plugin-missing)       reason=$(jq -Rn --arg r "$(entry_reason missing)" '$r') ;;
      *)                    reason=$(jq -Rn --arg r "$(entry_reason not_enabled)" '$r') ;;
    esac
  elif [ ! -r "$(bash "$HERE/executors" path "$id" runner 2>/dev/null)" ]; then
    # Registered but broken: an installation fault rather than an executor
    # state, so the message is generated rather than taken from the map.
    reason=$(jq -Rn --arg r "the $id executor is registered but its runner is missing" '$r')
  elif [ "$authed" = false ]; then
    reason=$(jq -Rn --arg r "$(entry_reason logged_out)" '$r')
  elif [ "$auth_status" = probe_failed ]; then
    reason=$(jq -Rn --arg r "$(entry_reason probe_failed)" '$r')
  else
    usable=true
  fi

  jq -n \
    --arg id "$id" \
    --argjson present "$present" \
    --argjson version "$version" \
    --argjson authed "$authed" \
    --arg auth_status "$auth_status" \
    --argjson batch_capable true \
    --argjson usable "$usable" \
    --argjson reason "$reason" \
    --arg path "$path" \
    '{id:$id, present:$present, path:(if $path=="" then null else $path end),
      version:$version, authed:$authed, auth_status:$auth_status, batch_capable:$batch_capable,
      usable:$usable, reason:$reason}'
}

registered=$(bash "$HERE/executors" list 2>/dev/null)
if [ $# -gt 0 ]; then
  for id in "$@"; do
    grep -qxF -- "$id" <<<"$registered" || {
      printf "detect-executors: %s is not a registered executor; run 'executors list'\n" "$id" >&2
      exit 2
    }
  done
  ids=$(printf '%s\n' "$@")
else
  ids=$registered
fi
while IFS= read -r id; do
  [ -n "$id" ] || continue
  emit "$id"
done <<<"$ids" | jq -s '.'
