# turn_refs DIR — the repository's common git directory, then the distinct
# commits its local branches point at. Worktrees share both, so a commit, a
# merge or the deletion of a branch's only pointer changes the output from any
# of them; a new branch on an existing commit does not. Status 1 outside git.
turn_refs() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  printf '%s\n' "$common"
  git -C "$1" for-each-ref --format='%(objectname)' refs/heads 2>/dev/null | sort -u
}
