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
WAB_SANDBOX=${WAB_SANDBOX:-$WAB_HERE/sandbox}
WAB_WRITABLE=${WAB_WRITABLE:-}

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
# `env -i "${WAB_ENV[@]}" …`: a scratch home, the run's own Claude config
# directory, and git and gh with no way to reach a network remote.
wab_env() {
  local dir=$1
  mkdir -p "$dir/gh" "$dir/guard"
  WAB_ENV=(
    "PATH=$PATH" "HOME=$dir/home" "TERM=xterm-256color" "LANG=${LANG:-C.UTF-8}"
    "IS_SANDBOX=1" "CLAUDE_CONFIG_DIR=$dir/claude-config"
    "GIT_ALLOW_PROTOCOL=file" "GIT_SSH_COMMAND=false" "GIT_TERMINAL_PROMPT=0"
    "GH_CONFIG_DIR=$dir/gh" "WORKFLOW_GUARD_CLAUDE_DIR=$dir/guard"
    "GOCACHE=$dir/gocache" "DISABLE_AUTOUPDATER=1"
  )
}

# wab_run_config RUN_DIR — the run's own Claude config directory: copies of
# the owner's login, .claude.json and settings.json, so the nested session
# writes nothing the owner's own sessions read. A token refresh in the run
# stays in its copy. Made afresh each time: an earlier sandboxed command
# could have left a link in it that a copy would write through.
wab_run_config() {
  local cfg="$1/claude-config" f
  rm -rf -- "$cfg" && mkdir -m 700 -- "$cfg" || return 1
  for f in .credentials.json .claude.json settings.json; do
    if [ -e "$WAB_CLAUDE_CONFIG/$f" ]; then
      cp -L "$WAB_CLAUDE_CONFIG/$f" "$cfg/$f" && chmod 600 "$cfg/$f" || return 1
    fi
  done
}

# wab_sandbox_args RUN_DIR — set WAB_SANDBOX_ARGS to the sandbox options for
# a run: writable only the session's own directories in the run directory and
# each WAB_WRITABLE directory; the owner's Claude config directories and
# credentials hidden. The files the harness writes (state, arm.json, out/)
# stay out of reach, so the session cannot plant
# a link the harness would write through.
wab_sandbox_args() {
  local extra h d parts=()
  WAB_SANDBOX_ARGS=(-h "$WAB_CLAUDE_CONFIG")
  for d in clone home claude-config gh guard gocache; do
    mkdir -p -- "$1/$d" && WAB_SANDBOX_ARGS+=(-w "$1/$d")
  done
  [ "$WAB_CLAUDE_CONFIG" = "$HOME/.claude" ] || WAB_SANDBOX_ARGS+=(-h "$HOME/.claude")
  [ -z "$WAB_WRITABLE" ] || IFS=: read -ra parts <<<"$WAB_WRITABLE"
  for extra in "${parts[@]}"; do [ -n "$extra" ] && WAB_SANDBOX_ARGS+=(-w "$extra"); done
  for h in .ssh .gnupg .config/gh .aws .docker .kube .dforge .netrc .git-credentials; do
    WAB_SANDBOX_ARGS+=(-h "$HOME/$h")
  done
}

