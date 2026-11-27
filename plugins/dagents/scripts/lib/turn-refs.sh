# turn_refs DIR — the repository's common git directory, DIR's worktree, then
# one "<commit><TAB><worktree>" line per distinct pair: the worktree that has
# a branch checked out, or nothing; branches at one commit with no worktree
# share a line. Status 1 outside git.
turn_refs() {
  local common top
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  printf '%s\n%s\n' "$common" "$top"
  git -C "$1" for-each-ref --format='%(objectname)%09%(worktreepath)' refs/heads 2>/dev/null | sort -u
}

# turn_primary COMMON — the primary checkout of the repository whose common git
# directory is COMMON: its parent, or else the first worktree git lists for it.
# Status 1 when that directory is gone.
turn_primary() {
  local dir
  [ -n "$1" ] || return 1
  case "$1" in
    */.git) dir=${1%/.git} ;;
    *) dir=$(git --git-dir="$1" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n '1s/^worktree //p') ;;
  esac
  [ -n "$dir" ] && [ -d "$dir" ] && printf '%s\n' "$dir"
}
