# turn_refs DIR — the repository's common git directory, DIR's worktree, then
# one "<commit><TAB><worktree>" line per local branch: the worktree that has it
# checked out, or nothing. Status 1 outside git.
turn_refs() {
  local common top
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  printf '%s\n%s\n' "$common" "$top"
  git -C "$1" for-each-ref --format='%(objectname)%09%(worktreepath)' refs/heads 2>/dev/null | sort -u
}
