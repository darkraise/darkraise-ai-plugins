# Sourced. A repository's dagents directories: .dagents/ and docs/dagents/.

# dagents_dir state|docs [ROOT] — the directory under ROOT (default: .).
dagents_dir() {
  local root=${2:-.} leaf
  case ${1:-} in
    state) leaf=.dagents ;;
    docs) leaf=docs/dagents ;;
    *) printf 'dagents_dir: unknown kind %s (state or docs)\n' "${1:-}" >&2; return 2 ;;
  esac
  printf '%s/%s\n' "$root" "$leaf"
}

# dagents_self_ignore DIR — give the existing directory DIR a self-ignoring
# .gitignore: nothing under it is ever committed, and the host repository need
# not list it. An existing .gitignore is left as it is. A cloned repository
# controls both names, so neither is written through a symbolic link, and
# noclobber refuses a file that appears between the test and the write.
dagents_self_ignore() {
  local dir=$1
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ ! -e "$dir/.gitignore" ] && [ ! -L "$dir/.gitignore" ] || return 0
  (set -C; printf '*\n' > "$dir/.gitignore") 2>/dev/null || true
}

# dagents_state_ignore [ROOT] — the same for ROOT's state directory, as
# .dagents/sdd/ has.
dagents_state_ignore() {
  local dir
  dir=$(dagents_dir state "${1:-.}") || return
  dagents_self_ignore "$dir"
}

# dagents_dir_rel state|docs [ROOT] — the same directory, relative to ROOT.
dagents_dir_rel() {
  local dir
  dir=$(dagents_dir "$@") || return
  printf '%s\n' "${dir#"${2:-.}"/}"
}

# dagents_legacy_layout [ROOT] — each older path of the checkout at ROOT
# (default: .) that still exists, one per line: dr-superpowers' (before 3.0)
# and dr-forge's (3.x) state directories .superpowers/ and .forge/, docs trees
# docs/superpowers/ and docs/forge/, its git dir's dr-superpowers/ and
# dr-forge/, and the primary checkout's .superpowers/ and .forge/, which hold a
# linked worktree's handoff. It also names ~/.dr-superpowers when that home is
# unmigrated (its config holds a darkmem mapping the new config lacks, or its
# mirror folder still holds a mirror) and ~/.dr-forge while it holds anything.
# dagents reads none of them, so the migrate skill must move them first.
dagents_legacy_layout() {
  local root=${1:-.} gitdir common primary home=${HOME:-}/.dr-superpowers name
  if [ -n "${HOME:-}" ] && {
    { grep -qs '"darkmem"[[:space:]]*:' "$home/config.json" && ! grep -qs '"darkmem"[[:space:]]*:' "${HOME}/.dagents/config.json"; } ||
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

# dagents_dforge5_plan [ROOT] — the first plan under ROOT/docs/dforge/plans/
# that its completed.md does not record and whose "### Task" headings include
# one with no **Implementer:** line before the next: dforge 5 writes none, and
# its layout is not one dagents can migrate. Prints the plan's name
# (docs/dforge/plans/<rest>); status 1 when there is none. A fenced block is
# quoted text, never a heading.
dagents_dforge5_plan() {
  local docs=${1:-.}/docs/dforge plan rel index spelling recorded
  [ -d "$docs/plans" ] || return 1
  while IFS= read -r -d '' plan; do
    rel=${plan#"$docs"/}
    [ "${rel##*/}" != completed.md ] || continue
    index="$(dirname -- "$plan")/completed.md" recorded=0
    if [ -f "$index" ]; then
      for spelling in dforge dagents forge superpowers; do
        grep -qF "\`docs/$spelling/$rel\`" "$index" && { recorded=1; break; }
      done
    fi
    [ "$recorded" -eq 0 ] || continue
    awk '
      function close_task() { if (task && !impl) bad = 1 }
      /^ ? ? ?(```|~~~)/ { fence = !fence; next }
      fence { next }
      /^### Task / { close_task(); task = 1; impl = 0; next }
      /^\*\*Implementer:\*\*/ { impl = 1 }
      END { close_task(); exit bad ? 0 : 1 }
    ' "$plan" && { printf 'docs/dforge/%s\n' "$rel"; return 0; }
  done < <(find "$docs/plans" -type f -name '*.md' -print0 2>/dev/null | sort -z)
  return 1
}

# dagents_dforge4_layout [ROOT] — true when the checkout at ROOT still holds
# dforge 4.x's docs/dforge/ or .dforge/ and no dforge 5 plan, so the migrate
# skill can move it to dagents' names.
dagents_dforge4_layout() {
  local root=${1:-.}
  [ -e "$root/docs/dforge" ] || [ -e "$root/.dforge" ] || return 1
  ! dagents_dforge5_plan "$root" > /dev/null
}
