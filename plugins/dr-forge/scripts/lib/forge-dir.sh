# Sourced. A repository's dr-forge directories: .forge/ and docs/forge/.

# forge_dir state|docs [ROOT] — the directory under ROOT (default: .).
forge_dir() {
  local root=${2:-.} leaf
  case ${1:-} in
    state) leaf=.forge ;;
    docs) leaf=docs/forge ;;
    *) printf 'forge_dir: unknown kind %s (state or docs)\n' "${1:-}" >&2; return 2 ;;
  esac
  printf '%s/%s\n' "$root" "$leaf"
}

# forge_dir_rel state|docs [ROOT] — the same directory, relative to ROOT.
forge_dir_rel() {
  local dir
  dir=$(forge_dir "$@") || return
  printf '%s\n' "${dir#"${2:-.}"/}"
}

# forge_legacy_layout [ROOT] — each pre-3.0 path of the checkout at ROOT
# (default: .) that still exists, one per line: its .superpowers/ and
# docs/superpowers/, its git dir's dr-superpowers/, and the primary checkout's
# .superpowers/, which holds a linked worktree's handoff. It also names
# ~/.dr-superpowers when that home is unmigrated: its config holds a darkmem
# mapping the new config lacks, or its mirror folder still holds a mirror.
# dr-forge reads none of them since 3.0.0, so scripts/forge-migrate must move
# them first.
forge_legacy_layout() {
  local root=${1:-.} gitdir common primary home=${HOME:-}/.dr-superpowers
  if [ -n "${HOME:-}" ] && {
    { grep -qs '"darkmem"[[:space:]]*:' "$home/config.json" && ! grep -qs '"darkmem"[[:space:]]*:' "${HOME}/.dr-forge/config.json"; } ||
    [ -n "$(ls -A "$home/mirror" 2>/dev/null)" ]
  }; then printf '%s\n' "$home"; fi
  [ ! -e "$root/.superpowers" ] || printf '%s\n' "$root/.superpowers"
  [ ! -e "$root/docs/superpowers" ] || printf '%s\n' "$root/docs/superpowers"
  gitdir=$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null) || return 0
  [ ! -e "$gitdir/dr-superpowers" ] || printf '%s\n' "$gitdir/dr-superpowers"
  common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ "$common" != "$gitdir" ] || return 0
  primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ ! -e "$primary/.superpowers" ] || printf '%s\n' "$primary/.superpowers"
  return 0
}
