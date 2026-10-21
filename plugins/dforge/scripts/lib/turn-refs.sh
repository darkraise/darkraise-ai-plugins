# turn_refs DIR — the repository's common git directory, DIR's worktree, then
# one "<commit><TAB><worktree>" line per local branch: the worktree that has it
# checked out, or nothing. Worktrees share the branches, so a commit, a merge
# or the deletion of a branch's only pointer shows from any of them. Status 1
# outside git.
turn_refs() {
  local common top
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  printf '%s\n%s\n' "$common" "$top"
  git -C "$1" for-each-ref --format='%(objectname)%09%(worktreepath)' refs/heads 2>/dev/null | sort -u
}

# turn_refs_moved WAS NOW TOP… — whether a branch moved between two turn_refs
# outputs: a commit some branch pointed at appeared or vanished. A commit held
# by a branch checked out in a worktree other than the TOPs is left out:
# another session works there, and its commits are not this turn's.
turn_refs_moved() {
  local was=$1 now=$2
  shift 2
  # A stamp written before the worktree column holds a commit, not a path, on
  # its second line; every branch would read as moved once.
  [[ $(sed -n 2p <<<"$was") =~ ^[0-9a-f]{40,64}$ ]] && return 1
  { tail -n +3 <<<"$was" | sed 's/^/w\t/'; tail -n +3 <<<"$now" | sed 's/^/n\t/'; } |
    awk -F'\t' -v tops="$(printf '%s\n' "$@")" '
      BEGIN { n = split(tops, t, "\n"); for (i = 1; i <= n; i++) mine[t[i]] = 1 }
      NF >= 2 { seen[$1, $2] = 1; all[$2] = 1; if ($3 != "" && !($3 in mine)) other[$2] = 1 }
      END { for (c in all) if (!(c in other) && seen["w", c] != seen["n", c]) moved = 1; exit !moved }'
}
