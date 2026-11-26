# Sourced by scripts/auto-run after lib/auto-run.sh. What would stop an
# unattended run, checked before the spec review while the owner is present.

# _preflight_space PATH THRESHOLD — the line for PATH when its filesystem has
# less than THRESHOLD percent free; nothing when df cannot answer.
_preflight_space() {
  local used free
  used=$(df -P "$1" 2>/dev/null | awk 'NR > 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+%$/) { sub(/%/, "", $i); print $i; exit } }')
  [ -n "$used" ] || return 1
  free=$((100 - used))
  [ "$free" -lt "$2" ] || return 1
  printf 'preflight: free space %s%% on %s (below %s%%)\n' "$free" "$1" "$2"
}

_preflight_first() { head -n 1 | tr -d '\r'; }

# preflight_run ISOLATION — the blocker lines (or `preflight: ok`), then one
# review line per family of scripts/executors ranked.
preflight_run() {
  local iso=$1 scripts top primary threshold=${DFORGE_PREFLIGHT_FREE:-15} line err dir refdir probe made=0 existed id gate setting
  local -a lines=()
  scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  [[ $threshold =~ ^[0-9]+$ ]] || threshold=15
  top=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
  [ -n "$top" ] || top=$PWD
  primary=$(ar_primary_root 2>/dev/null | tr -d '\r')
  [ -n "$primary" ] || primary=$top

  for dir in "$top" "${TMPDIR:-/tmp}"; do
    line=$(_preflight_space "$dir" "$threshold") && lines+=("$line")
  done

  # git keeps a ref's emptied directory, so one the probe created goes too.
  refdir=$(git -C "$primary" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')/refs/dforge
  [ ! -e "$refdir" ] || refdir=""
  if err=$(git -C "$primary" update-ref refs/dforge/preflight HEAD 2>&1 >/dev/null); then
    git -C "$primary" update-ref -d refs/dforge/preflight >/dev/null 2>&1
    [ -z "$refdir" ] || rmdir "$refdir" 2>/dev/null
  else
    lines+=("preflight: git write refused in $primary: $(_preflight_first <<<"$err")")
  fi

  if [ "$iso" = worktree ]; then
    if [ -e "$primary/.worktrees" ]; then dir=$primary/.worktrees
    elif [ -e "$primary/worktrees" ]; then dir=$primary/worktrees
    else dir=$primary/.worktrees; fi
    [ -e "$dir" ] || made=1
    probe=$dir/dforge-preflight-$$
    existed=0
    [ ! -e "$probe" ] || existed=1
    if err=$(git -C "$primary" worktree add --detach "$probe" HEAD 2>&1 >/dev/null); then
      git -C "$primary" worktree remove --force "$probe" >/dev/null 2>&1
    else
      lines+=("preflight: scratch worktree refused in $dir: $(_preflight_first <<<"$err")")
    fi
    [ "$existed" = 1 ] || rm -rf "$probe" 2>/dev/null
    git -C "$primary" worktree prune >/dev/null 2>&1
    [ "$made" = 0 ] || rmdir "$dir" 2>/dev/null
  fi

  [ "${#lines[@]}" -gt 0 ] || echo "preflight: ok"
  [ "${#lines[@]}" -eq 0 ] || printf '%s\n' "${lines[@]}"

  while IFS= read -r id; do
    id=${id//$'\r'/}
    [ -n "$id" ] || continue
    gate=$(bash "$scripts/$id-gate" 2>/dev/null | _preflight_first)
    setting=off
    [ "$(dforge_setting "${id}Review" false)" != true ] || setting=on
    printf 'preflight: review %s: %s — setting %s\n' "$id" "${gate#"$id-gate "}" "$setting"
  done < <(bash "$scripts/executors" ranked 2>/dev/null)
  return 0
}
