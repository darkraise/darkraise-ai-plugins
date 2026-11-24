# shellcheck shell=bash
# Shared by the workflow-ab scripts: the parameters (README.md), the run
# directory and logging. Sourced, never run.

WAB_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WAB_ROOT=${WAB_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/workflow-ab}
WAB_SOURCE=${WAB_SOURCE:-}
WAB_BASE=${WAB_BASE:-}
WAB_PLAN=${WAB_PLAN:-}
WAB_PLUGINS=${WAB_PLUGINS:-$(cd "$WAB_HERE/../.." && pwd)}
WAB_CLAUDE_CONFIG=${WAB_CLAUDE_CONFIG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}
WAB_DFORGE_CONFIG=${WAB_DFORGE_CONFIG:-$HOME/.dforge/config.json}
WAB_CLAUDE=${WAB_CLAUDE:-/root/.local/bin/claude}
WAB_TMUX=${WAB_TMUX:-tmux}

WAB_C14='- This is a replay in a clone with no remote: no push, tag or workflow dispatch; a gate that needs one is recorded as not run.'

wab_log() { printf 'workflow-ab: %s\n' "$*" >&2; }
wab_die() { # wab_die STATUS MESSAGE
  wab_log "$2"
  exit "$1"
}

# /tmp is memory-backed on the replay hosts, and a replay's clone, caches and
# transcripts outgrow it.
wab_check_root() {
  case $WAB_ROOT in
    /tmp|/tmp/*) wab_die 2 "WAB_ROOT must not be under /tmp" ;;
  esac
}

wab_check_arm() {
  case ${1:-} in
    dforge|dagents) ;;
    *) wab_die 2 "ARM must be dforge or dagents" ;;
  esac
}

wab_run_dir() { # wab_run_dir ARM RUN
  printf '%s/%s-%s\n' "$WAB_ROOT" "$1" "$2"
}

wab_plugin_dir() { printf '%s/plugins/%s\n' "$WAB_PLUGINS" "$1"; }

# wab_env RUN_DIR — set WAB_ENV to the nested session's whole environment, for
# `env -i "${WAB_ENV[@]}" …`: a scratch home, the owner's config directory for
# the login only, and git and gh with no way to reach a network remote.
wab_env() {
  local dir=$1
  mkdir -p "$dir/gh" "$dir/guard"
  WAB_ENV=(
    "PATH=$PATH" "HOME=$dir/home" "TERM=xterm-256color" "LANG=${LANG:-C.UTF-8}"
    "IS_SANDBOX=1" "CLAUDE_CONFIG_DIR=$WAB_CLAUDE_CONFIG"
    "GIT_ALLOW_PROTOCOL=file" "GIT_SSH_COMMAND=false" "GIT_TERMINAL_PROMPT=0"
    "GH_CONFIG_DIR=$dir/gh" "WORKFLOW_GUARD_CLAUDE_DIR=$dir/guard"
    "GOCACHE=$dir/gocache"
  )
}

# Accepting the bypass prompt writes skipDangerousModePermissionPrompt into the
# owner's settings.json even with user settings sources off. Each launch
# records whether the key was there before in <run>/settings-repair; this
# removes a key the harness saw appear, and runs at the start of every command
# so a killed launch's removal is finished by the next one.
wab_settings_repair() {
  local marker file before tmp status=0
  for marker in "$WAB_ROOT"/*/settings-repair; do
    [ -f "$marker" ] || continue
    before=$(sed -n 's/^keyBefore=//p' "$marker")
    file=$(sed -n 's/^file=//p' "$marker")
    # A symlinked settings.json is rewritten at its target, so the link stays.
    [ -e "$file" ] && file=$(readlink -f "$file")
    if [ "$before" = absent ] && [ -f "$file" ] \
      && jq -e 'has("skipDangerousModePermissionPrompt")' < "$file" >/dev/null 2>&1; then
      tmp=$(mktemp "$file.wab.XXXXXX") || { status=1; continue; }
      if jq 'del(.skipDangerousModePermissionPrompt)' < "$file" > "$tmp" && chmod --reference="$file" "$tmp" \
        && mv -f "$tmp" "$file"; then
        :
      else
        rm -f "$tmp"
        status=1
        continue
      fi
    fi
    rm -f "$marker"
  done
  return "$status"
}
