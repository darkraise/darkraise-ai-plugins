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

# The local Codex model catalog, as a negative filter. A pair absent from it is
# never attempted; a pair present in it is attempted and the seat runner's
# outcome policy carries the guarantee. Catalog listing is not entitlement:
# gpt-5.6-luna and gpt-5.6-terra were listed on 2026-09-14 and were rejected
# with HTTP 400 on this account on 2026-08-31.
#
# null and an empty pair list are different facts and must stay
# distinguishable: null means no usable catalog was read, [] means one was read
# and advertised nothing.
advertised_pairs() {
  local cache="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
  [ -r "$cache" ] || { printf 'null'; return; }
  # Validate before extracting. A cache that is a valid object followed by
  # trailing bytes - a half-written file during a concurrent codex run - makes
  # jq print the object and *then* fail, so an unguarded `|| printf null`
  # appends to real output and yields "{...}null". --argjson would reject that
  # and emit() would produce nothing, dropping the codex row from the roster
  # entirely: a silent loss of the whole lane.
  jq -e . "$cache" >/dev/null 2>&1 || { printf 'null'; return; }
  jq -c '{fetched_at: .fetched_at, client_version: .client_version,
          pairs: [.models[]? | select(.visibility == "list") as $m
                  | $m.supported_reasoning_levels[]?
                  | {model: $m.slug, effort: .effort}]}' "$cache" 2>/dev/null \
    || printf 'null'
}

emit() { # emit <id> <batch_capable> <lane_implemented> <incapable_reason>
  local id="$1" capable="$2" lane="$3" incapable_reason="$4"
  local path present version authed reason usable auth_status=not_applicable advertised=null

  path=$(command -v "$id" 2>/dev/null || true)
  if [ -n "$path" ]; then present=true; else present=false; fi

  version=null
  if [ "$present" = true ]; then
    local v
    v=$(timeout 20 "$id" --version 2>/dev/null | head -1 | tr -d '\r')
    [ -n "$v" ] && version=$(jq -Rn --arg v "$v" '$v')
  fi

  authed=null
  if [ "$id" = codex ] && [ "$present" = true ]; then
    local auth_output auth_rc
    auth_output=$(timeout 20 "$id" login status 2>&1)
    auth_rc=$?
    auth_output="${auth_output//$'\r'/}"
    auth_status=probe_failed
    if [ "$auth_rc" -eq 0 ] && [[ "$auth_output" == 'Logged in using '* ]]; then
      authed=true; auth_status=authenticated
    elif [ "$auth_rc" -eq 1 ] && [ "$auth_output" = 'Not logged in' ]; then
      authed=false; auth_status=logged_out
    fi
  fi

  if [ "$id" = codex ] && [ "$present" = true ]; then
    advertised=$(advertised_pairs)
  fi

  usable=false
  reason=null
  if [ "$present" != true ]; then
    reason='"not on PATH"'
  elif [ "$capable" != true ]; then
    reason=$(jq -Rn --arg r "$incapable_reason" '$r')
  elif [ "$lane" != true ]; then
    reason=$(jq -Rn --arg r "no executor lane is implemented for $id in this plugin; only codex has a wrapper" '$r')
  elif [ "$authed" = false ]; then
    reason='"present but not authenticated; run codex login"'
  elif [ "$auth_status" = probe_failed ]; then
    reason='"authentication status probe failed; check codex login status"'
  elif [ "$version" = null ]; then
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
    --argjson advertised "$advertised" \
    --arg path "$path" \
    '{id:$id, present:$present, path:(if $path=="" then null else $path end),
      version:$version, authed:$authed, auth_status:$auth_status, batch_capable:$batch_capable,
      usable:$usable, reason:$reason, advertised:$advertised}'
}

{
  emit codex true true ""
  emit cursor-agent true false ""
  emit opencode true false ""
  emit antigravity false false "installed, but its only agent mode (antigravity chat -m agent) opens a GUI editor session with no output file, no completion signal, and no exit code tied to the work"
} | jq -s '.'
