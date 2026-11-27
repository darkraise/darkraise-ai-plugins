#!/usr/bin/env bash
# Worktree snapshots: the tracked and untracked files, the index and HEAD of a
# checkout, recorded so a run that must not write can be proved not to have.

dr_state_error() { printf 'worktree-snapshot: %s\n' "$1" >&2; return 2; }
dr_canonical() { (cd -- "$1" && pwd -P); }

# dr_index_record DIR - the index of DIR's whole worktree, base64. -v tags an
# assume-unchanged entry in lower case and a skip-worktree entry S, flags
# --stage alone never prints.
dr_index_record() {
  local top
  top="$(git -C "$1" rev-parse --show-toplevel)" || return 2
  git -C "$top" ls-files --stage -v -z | base64 | tr -d '\r\n'
}

dr_snapshot() {
  local root output="$2" index files temp indexfile filesfile filemode
  # The whole worktree, whichever directory of it was given.
  root="$(git -C "$1" rev-parse --show-toplevel)" && root="$(dr_canonical "$root")" || return 2
  temp="$(mktemp "${output}.XXXXXX")" || return 2
  index="$(dr_index_record "$root")" || { rm -f "$temp"; return 2; }
  filemode=$(git -C "$root" config --bool core.filemode) || filemode=false
  files="$({ git -C "$root" ls-tree -r --name-only -z HEAD; git -C "$root" ls-files -c -o --exclude-standard -z; } | sort -zu |
    _dr_snapshot_entries "$root" "$filemode" | jq -Rs 'split("\u0000") | . as $f |
    [range(0; length - 1; 4) as $i |
      {path:$f[$i], hash:$f[$i+1], mode:$f[$i+2], kind:$f[$i+3]}] |
    sort_by(.path)')" || { rm -f "$temp"; return 2; }
  local head gitdir
  head="$(git -C "$root" rev-parse HEAD)" || { rm -f "$temp"; return 2; }
  gitdir="$(git -C "$root" rev-parse --absolute-git-dir)" || { rm -f "$temp"; return 2; }
  gitdir="$(dr_canonical "$gitdir")" || { rm -f "$temp"; return 2; }
  # The index and the manifest both scale with the repository, and a command
  # line is bounded - 32767 bytes on Windows. Passing them as arguments made
  # the snapshot fail outright past a few hundred files, so both reach jq as
  # files. --rawfile takes the index verbatim and --slurpfile parses the
  # manifest, which keeps the output byte-identical to the argument form.
  indexfile="$(mktemp "${output}.idx.XXXXXX")" || { rm -f "$temp"; return 2; }
  filesfile="$(mktemp "${output}.fls.XXXXXX")" || { rm -f "$temp" "$indexfile"; return 2; }
  printf '%s' "$index" > "$indexfile" || { rm -f "$temp" "$indexfile" "$filesfile"; return 2; }
  printf '%s' "$files" > "$filesfile" || { rm -f "$temp" "$indexfile" "$filesfile"; return 2; }
  jq -n --arg root "$root" --arg gitdir "$gitdir" --arg head "$head" \
    --rawfile index "$indexfile" --slurpfile files "$filesfile" \
    '{root:$root,gitdir:$gitdir,head:$head,index:$index,files:$files[0]}' > "$temp" &&
    mv -f -- "$temp" "$output" || { rm -f "$temp" "$indexfile" "$filesfile"; return 2; }
  rm -f "$indexfile" "$filesfile"
}

# _dr_snapshot_entries ROOT FILEMODE: NUL-separated paths on stdin become
# path, hash, mode, kind records. Regular files are hashed in one
# `hash-object --stdin-paths` call: a process per file made a snapshot of a
# 2,000-file repository take seconds, and a task takes several snapshots.
# Symlinks, and names --stdin-paths cannot carry verbatim (a newline or
# carriage return, or a leading quote, which it unquotes C-style), are still
# hashed one at a time. A directory is accepted only as a registered
# submodule, recorded by its checked-out commit (_dr_submodule_head).
_dr_snapshot_entries() {
  local root="$1" filemode="$2" path hash mode n=0 i=0
  local paths=() hashes=() modes=() kinds=() batch=()
  while IFS= read -r -d '' path; do
    paths+=("$path")
    if [ -L "$root/$path" ]; then
      hash="$(readlink -- "$root/$path" | git -C "$root" hash-object --stdin)" || return 2
      hashes+=("$hash"); modes+=(120000); kinds+=(symlink)
    elif [ -f "$root/$path" ]; then
      mode=100644
      if [ "$filemode" = true ] && [ -x "$root/$path" ]; then mode=100755; fi
      case "$path" in
        *$'\n'*|*$'\r'*|\"*) hash="$(git -C "$root" hash-object --no-filters -- "$path")" || return 2 ;;
        *) hash=''; batch+=("$n") ;;
      esac
      hashes+=("$hash"); modes+=("$mode"); kinds+=(file)
    elif [ -d "$root/$path" ]; then
      hash="$(_dr_submodule_head "$root" "$path" </dev/null)" || return 2
      hashes+=("$hash"); modes+=(160000); kinds+=(gitlink)
    elif [ ! -e "$root/$path" ]; then hashes+=(''); modes+=(0); kinds+=(deleted)
    else return 2
    fi
    n=$((n + 1))
  done
  if [ "${#batch[@]}" -gt 0 ]; then
    while IFS= read -r hash; do
      hashes[${batch[i]}]="${hash%$'\r'}"; i=$((i + 1))
    done < <(for n in "${batch[@]}"; do printf '%s\n' "${paths[n]}"; done |
      git -C "$root" hash-object --no-filters --stdin-paths)
    # The process substitution hides git's status, so a short answer is the
    # failure signal.
    [ "$i" -eq "${#batch[@]}" ] || return 2
  fi
  # NUL delimiters preserve tabs/newlines and other JSON-special filename
  # characters. Serialize once for the whole tree, not once per file.
  for ((i = 0; i < ${#paths[@]}; i++)); do
    printf '%s\0%s\0%s\0%s\0' "${paths[i]}" "${hashes[i]}" "${modes[i]}" "${kinds[i]}" || return 2
  done
}

# _dr_is_gitlink ROOT PATH [COMMIT] — whether the index, or COMMIT (default
# HEAD), records PATH as a submodule.
_dr_is_gitlink() {
  local entry
  entry="$(git --literal-pathspecs -C "$1" ls-files -s -- "$2")" || return 1
  if [ -z "$entry" ] || [ -n "${3:-}" ]; then
    entry="$(git --literal-pathspecs -C "$1" ls-tree "${3:-HEAD}" -- "$2")" || return 1
  fi
  [[ "$entry" == "160000 "* ]]
}

# _dr_submodule_head ROOT PATH — the commit a registered submodule has checked
# out, or nothing when it is not initialized. The worktree is written by the
# executor, so a nested .git is never trusted: only a gitfile into this
# repository's own modules directory is read, with config-driven commands
# off, and a dirty submodule is refused rather than summarized.
_dr_submodule_head() {
  local root="$1" path="$2" dir="$1/$2" link gitdir common head dirty
  _dr_is_gitlink "$root" "$path" || { dr_state_error "unregistered directory in worktree: $path"; return 2; }
  if [ ! -e "$dir/.git" ] && [ ! -L "$dir/.git" ]; then
    [ -z "$(ls -A -- "$dir")" ] || { dr_state_error "uninitialized submodule has files: $path"; return 2; }
    return 0
  fi
  [ -f "$dir/.git" ] && [ ! -L "$dir/.git" ] && IFS= read -r link < "$dir/.git" && [[ "$link" == 'gitdir: '* ]] ||
    { dr_state_error "submodule git directory is not a gitfile: $path"; return 2; }
  link="${link#gitdir: }"; link="${link%$'\r'}"
  case "$link" in /*|[A-Za-z]:*) ;; *) link="$dir/$link" ;; esac
  gitdir="$(dr_canonical "$link")" || return 2
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)" || return 2
  common="$(dr_canonical "$common")" || return 2
  case "$gitdir" in
    "$common"/modules/*|"$common"/worktrees/*/modules/*) ;;
    *) dr_state_error "submodule git directory is outside this repository: $path"; return 2 ;;
  esac
  set -- git -c core.fsmonitor=false -c core.untrackedCache=false -c core.hooksPath=/dev/null \
    --git-dir="$gitdir" --work-tree="$dir"
  head="$("$@" rev-parse --verify -q HEAD)" || { dr_state_error "submodule has no commit: $path"; return 2; }
  dirty="$("$@" status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" || return 2
  [ -z "$dirty" ] || { dr_state_error "submodule has uncommitted changes: $path"; return 2; }
  printf '%s' "$head"
}

dr_task_assert_snapshot() {
  local expected="$1" actual root
  root="$(jq -er .root "$expected")" || return 2
  actual="$(mktemp)" || return 2
  dr_snapshot "$root" "$actual" || { rm -f "$actual"; return 2; }
  jq -e --slurpfile actual "$actual" '. == $actual[0]' "$expected" >/dev/null
  local result=$?
  rm -f "$actual"
  return "$result"
}
