#!/usr/bin/env bash
# Emits a JSON roster of external agent CLIs. Read at plan time to populate the
# executor checkbox, and again at dispatch as a guard, because a roster can go
# stale between the two.
#
# batch_capable is a static fact about a tool, not a probe result: it records
# whether the CLI can run a task headlessly and return a result a script can
# read. Antigravity fails that test on its interface, not on its installation.
set -uo pipefail

emit() { # emit <id> <batch_capable> <incapable_reason>
  local id="$1" capable="$2" incapable_reason="$3"
  local path present version authed reason usable

  path=$(command -v "$id" 2>/dev/null || true)
  if [ -n "$path" ]; then present=true; else present=false; fi

  version=null
  if [ "$present" = true ]; then
    local v
    v=$(timeout 20 "$id" --version 2>/dev/null | head -1 | tr -d '\r')
    [ -n "$v" ] && version=$(jq -Rn --arg v "$v" '$v')
  fi

  # Auth is only checkable offline for codex, whose credentials live in a file.
  # For everything else the honest answer is null, not a guess.
  authed=null
  if [ "$id" = codex ] && [ "$present" = true ]; then
    if [ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]; then authed=true; else authed=false; fi
  fi

  usable=false
  reason=null
  if [ "$present" != true ]; then
    reason='"not on PATH"'
  elif [ "$capable" != true ]; then
    reason=$(jq -Rn --arg r "$incapable_reason" '$r')
  elif [ "$authed" = false ]; then
    reason='"present but not authenticated; run codex login"'
  else
    usable=true
  fi

  jq -n \
    --arg id "$id" \
    --argjson present "$present" \
    --argjson version "$version" \
    --argjson authed "$authed" \
    --argjson batch_capable "$capable" \
    --argjson usable "$usable" \
    --argjson reason "$reason" \
    --arg path "$path" \
    '{id:$id, present:$present, path:(if $path=="" then null else $path end),
      version:$version, authed:$authed, batch_capable:$batch_capable,
      usable:$usable, reason:$reason}'
}

{
  emit codex true ""
  emit cursor-agent true ""
  emit opencode true ""
  emit antigravity false "installed, but its only agent mode (antigravity chat -m agent) opens a GUI editor session with no output file, no completion signal, and no exit code tied to the work"
} | jq -s '.'
