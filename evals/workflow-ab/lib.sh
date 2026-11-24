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
