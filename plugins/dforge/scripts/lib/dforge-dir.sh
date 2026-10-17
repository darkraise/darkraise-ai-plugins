# Sourced. A repository's dforge directories: .dforge/ and docs/dforge/.

# dforge_dir state|docs [ROOT] — the directory under ROOT (default: .).
dforge_dir() {
  local root=${2:-.} leaf
  case ${1:-} in
    state) leaf=.dforge ;;
    docs) leaf=docs/dforge ;;
    *) printf 'dforge_dir: unknown kind %s (state or docs)\n' "${1:-}" >&2; return 2 ;;
  esac
  printf '%s/%s\n' "$root" "$leaf"
}

# dforge_self_ignore DIR — give the existing directory DIR a self-ignoring
# .gitignore: nothing under it is ever committed, and the host repository need
# not list it. An existing .gitignore is left as it is. A cloned repository
# controls both names, so neither is written through a symbolic link, and
# noclobber refuses a file that appears between the test and the write.
dforge_self_ignore() {
  local dir=$1
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ ! -e "$dir/.gitignore" ] && [ ! -L "$dir/.gitignore" ] || return 0
  (set -C; printf '*\n' > "$dir/.gitignore") 2>/dev/null || true
}

# dforge_state_ignore [ROOT] — the same for ROOT's state directory, as
# .dforge/sdd/ has.
dforge_state_ignore() {
  local dir
  dir=$(dforge_dir state "${1:-.}") || return
  dforge_self_ignore "$dir"
}

# dforge_dir_rel state|docs [ROOT] — the same directory, relative to ROOT.
dforge_dir_rel() {
  local dir
  dir=$(dforge_dir "$@") || return
  printf '%s\n' "${dir#"${2:-.}"/}"
}

# dforge_legacy_layout [ROOT] — each older path of the checkout at ROOT
# (default: .) that still exists, one per line: dr-superpowers' (before 3.0)
# and dr-forge's (3.x) state directories .superpowers/ and .forge/, docs trees
# docs/superpowers/ and docs/forge/, its git dir's dr-superpowers/ and
# dr-forge/, and the primary checkout's .superpowers/ and .forge/, which hold a
# linked worktree's handoff. It also names ~/.dr-superpowers when that home is
# unmigrated (its config holds a darkmem mapping the new config lacks, or its
# mirror folder still holds a mirror) and ~/.dr-forge while it holds anything.
# dforge reads none of them, so the migrate skill must move them first.
dforge_legacy_layout() {
  local root=${1:-.} gitdir common primary home=${HOME:-}/.dr-superpowers name
  if [ -n "${HOME:-}" ] && {
    { grep -qs '"darkmem"[[:space:]]*:' "$home/config.json" && ! grep -qs '"darkmem"[[:space:]]*:' "${HOME}/.dforge/config.json"; } ||
    [ -n "$(ls -A "$home/mirror" 2>/dev/null)" ]
  }; then printf '%s\n' "$home"; fi
  [ -z "${HOME:-}" ] || [ -z "$(ls -A "$HOME/.dr-forge" 2>/dev/null)" ] || printf '%s\n' "$HOME/.dr-forge"
  for name in .superpowers .forge docs/superpowers docs/forge; do
    [ ! -e "$root/$name" ] || printf '%s\n' "$root/$name"
  done
  gitdir=$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null) || return 0
  for name in dr-superpowers dr-forge; do
    [ ! -e "$gitdir/$name" ] || printf '%s\n' "$gitdir/$name"
  done
  common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ "$common" != "$gitdir" ] || return 0
  primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || return 0
  for name in .superpowers .forge; do
    [ ! -e "$primary/$name" ] || printf '%s\n' "$primary/$name"
  done
  return 0
}
