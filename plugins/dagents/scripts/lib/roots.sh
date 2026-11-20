# Sourced. Where a repository's dagents files live: the docs directory, the
# plan ledgers and their handoff.md, and the handoff files, all in the checkout.
# Defines functions only.
#
# Every helper takes an optional trailing DIR naming the checkout (default: the
# working directory). The roots are cached per HOME and checkout in shell
# variables; a helper called inside $(…) cannot fill the caller's cache, so a
# script that calls helpers repeatedly calls dagents_stores_init in its main
# shell first.

. "$(dirname "${BASH_SOURCE[0]}")/dagents-dir.sh"
. "$(dirname "${BASH_SOURCE[0]}")/native-path.sh"

_DAGENTS_KEY="" _DAGENTS_TOP="" _DAGENTS_DOCS_ROOT="" _DAGENTS_LEDGER_ROOT="" _DAGENTS_HANDOFF_DIR=""

# Git Bash compares paths in git's C:/… form, which is always long: git
# expands an 8.3 short name such as RUNNER~1 in a TEMP directory that cygpath
# keeps.
_dagents_path() {
  if command -v cygpath >/dev/null 2>&1; then _dagents_long "$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")"
  else printf '%s\n' "$1"; fi
}

# The long form of a C:/… path. GetLongPathName, behind cygpath -l, needs the
# path to exist, so the deepest existing ancestor is expanded and the rest kept.
_dagents_long() {
  local head=$1 tail=""
  while [ -n "$head" ] && [ ! -e "$head" ]; do
    case $head in */*) tail="/${head##*/}$tail" head=${head%/*} ;; *) head="" ;; esac
  done
  if [ -n "$head" ]; then printf '%s%s\n' "$(cygpath -m -l "$head" 2>/dev/null || printf '%s' "$head")" "$tail"
  else printf '%s\n' "$1"; fi
}

dagents_stores_init() { # [DIR]
  local dir=${1:-$PWD} top key base
  # Git Bash's $PWD is /tmp/... or /d/...; under MSYS_NO_PATHCONV git.exe takes
  # that form verbatim and finds no repository.
  top=$(git -C "$(dr_native_path "$dir")" rev-parse --show-toplevel 2>/dev/null) || top=""
  key="${HOME:-}|${top:-nogit:$dir}"
  [ "$_DAGENTS_KEY" = "$key" ] && return 0
  _DAGENTS_TOP=$top
  # Outside git, DIR stands in for the checkout.
  base=${top:-$dir}
  _DAGENTS_DOCS_ROOT=$(dagents_dir docs "$base")
  _DAGENTS_LEDGER_ROOT="$(dagents_dir state "$base")/sdd"
  _DAGENTS_HANDOFF_DIR="$(dagents_dir state "$base")/handoff"
  _DAGENTS_KEY=$key
}

dagents_docs_root() { dagents_stores_init "${1:-}"; printf '%s\n' "$_DAGENTS_DOCS_ROOT"; }
dagents_ledger_root() { dagents_stores_init "${1:-}"; printf '%s\n' "$_DAGENTS_LEDGER_ROOT"; }
dagents_ledger_dir() { dagents_stores_init "${2:-}"; printf '%s/%s\n' "$_DAGENTS_LEDGER_ROOT" "$1"; } # SLUG [DIR]

dagents_workspace() { # SLUG [DIR]
  dagents_stores_init "${2:-}"
  printf '%s/sdd/%s\n' "$(dagents_dir state "${_DAGENTS_TOP:-${2:-$PWD}}")" "$1"
}

# dagents_handoff_file KEY [DIR] — the handoff file of KEY under DIR's
# checkout's state directory. Exit 2 for a key that is no plain file name, or
# is latest.
dagents_handoff_file() {
  local key=$1
  if ! _dagents_handoff_key "$key"; then
    printf 'handoff: invalid key %s\n' "$key" >&2
    return 2
  fi
  dagents_stores_init "${2:-}"
  printf '%s/%s.md\n' "$_DAGENTS_HANDOFF_DIR" "$key"
}

# _dagents_handoff_key KEY — status 0 when KEY can name a handoff file. A file
# whose name is no key (an older layout's, which dagents-migrate renames) is
# not a handoff.
_dagents_handoff_key() { [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] && [ "$1" != latest ]; }
_dagents_handoff_listed() { local key=${1##*/}; [ -f "$1" ] && _dagents_handoff_key "${key%.md}"; }

# dagents_handoff_key_check KIND KEY — exit 2 when KEY cannot name a handoff
# of KIND: a plan or draft key that starts adhoc- or is latest, or an adhoc key
# that is neither adhoc-<8 hex digits> nor adhoc-legacy-*.
dagents_handoff_key_check() {
  case $1 in
    plan | draft) case $2 in adhoc-* | latest) return 2 ;; esac ;;
    adhoc) [[ $2 =~ ^adhoc-[0-9a-f]{8}$ || $2 =~ ^adhoc-legacy-[A-Za-z0-9._-]+$ ]] || return 2 ;;
    *) return 2 ;;
  esac
  return 0
}

# dagents_handoff_files [DIR] — every handoff/*.md of every checkout, in `git
# worktree list` order; never the claims/ or notes/ contents, nor a file whose
# name is no handoff key.
dagents_handoff_files() {
  local wt f
  dagents_stores_init "${1:-}"
  [ -n "$_DAGENTS_TOP" ] || return 0
  git -C "$(dr_native_path "$_DAGENTS_TOP")" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    wt=$(_dagents_path "$wt")
    [ -d "$wt" ] || continue
    for f in "$(dagents_dir state "$wt")"/handoff/*.md; do
      _dagents_handoff_listed "$f" && printf '%s\n' "$f"
    done
  done
  return 0
}

# dagents_ledger_files [DIR] — "<ledger>\t<checkout>" for every worktree's
# ledgers.
dagents_ledger_files() {
  local wt f
  dagents_stores_init "${1:-}"
  [ -n "$_DAGENTS_TOP" ] || return 0
  git -C "$_DAGENTS_TOP" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    for f in "$(dagents_dir state "$wt")"/sdd/*/progress.md; do
      [ -f "$f" ] && printf '%s\t%s\n' "$f" "$wt"
    done
  done
  return 0
}

# dagents_name_key NAME — the one name every docs prefix shares (store options
# spec §7.1): docs/superpowers/<rest> (before 3.0), docs/forge/<rest> (3.x)
# and docs/dforge/<rest> (dforge 4.x) are docs/dagents/<rest>. dagents writes
# only docs/dagents, but plans, specs, ledgers and registers written before it
# cite an old prefix and are never rewritten, so every comparison of two
# document names compares their keys.
dagents_name_key() {
  local name=${1#./}
  [ "$name" = / ] || name=${name%/}
  case $name in
    docs/superpowers|docs/forge|docs/dforge) printf 'docs/dagents\n' ;;
    docs/dforge/*) printf 'docs/dagents/%s\n' "${name#docs/dforge/}" ;;
    docs/superpowers/*) printf 'docs/dagents/%s\n' "${name#docs/superpowers/}" ;;
    docs/forge/*) printf 'docs/dagents/%s\n' "${name#docs/forge/}" ;;
    *) printf '%s\n' "$name" ;;
  esac
}

# dagents_name_spellings NAME — the key, then for a document name the same name
# under dforge 4.x's docs/dforge, the 3.x docs/forge and the pre-3.0
# docs/superpowers. completed.md and
# register cells keep the spelling they were written with, so a search runs
# once per line and accepts any.
dagents_name_spellings() {
  local key rest
  key=$(dagents_name_key "$1")
  printf '%s\n' "$key"
  case $key in
    docs/dagents) printf 'docs/dforge\ndocs/forge\ndocs/superpowers\n' ;;
    docs/dagents/*)
      rest=${key#docs/dagents/}
      printf 'docs/dforge/%s\ndocs/forge/%s\ndocs/superpowers/%s\n' "$rest" "$rest" "$rest" ;;
  esac
}

# dagents_resolve NAME [DIR] — a document name under the docs root, any other
# relative name under the worktree, an absolute path unchanged. A historical
# citation docs/superpowers/…, docs/forge/… or docs/dforge/… resolves as
# docs/dagents/… does.
dagents_resolve() {
  local name=${1#./}
  dagents_stores_init "${2:-}"
  case $name in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) printf '%s\n' "$1" ;;
    docs/dagents|docs/dforge|docs/forge|docs/superpowers) printf '%s\n' "$_DAGENTS_DOCS_ROOT" ;;
    docs/dagents/*) printf '%s/%s\n' "$_DAGENTS_DOCS_ROOT" "${name#docs/dagents/}" ;;
    docs/dforge/*) printf '%s/%s\n' "$_DAGENTS_DOCS_ROOT" "${name#docs/dforge/}" ;;
    docs/forge/*) printf '%s/%s\n' "$_DAGENTS_DOCS_ROOT" "${name#docs/forge/}" ;;
    docs/superpowers/*) printf '%s/%s\n' "$_DAGENTS_DOCS_ROOT" "${name#docs/superpowers/}" ;;
    *) printf '%s/%s\n' "${_DAGENTS_TOP:-${2:-$PWD}}" "$name" ;;
  esac
}

_dagents_name_of() { # ABSOLUTE — its name when it lies under a root; status 1 otherwise
  local docs_name
  docs_name=$(dagents_dir_rel docs "${_DAGENTS_TOP:-$PWD}")
  case $1 in
    "$_DAGENTS_DOCS_ROOT") printf '%s\n' "$docs_name"; return 0 ;;
    "$_DAGENTS_DOCS_ROOT"/*) printf '%s/%s\n' "$docs_name" "${1#"$_DAGENTS_DOCS_ROOT"/}"; return 0 ;;
  esac
  [ -n "$_DAGENTS_TOP" ] || return 1
  case $1 in "$_DAGENTS_TOP"/*) printf '%s\n' "${1#"$_DAGENTS_TOP"/}"; return 0 ;; esac
  return 1
}

# dagents_name FILE [DIR] — the inverse of dagents_resolve, computed from the roots.
# A relative FILE is a path from the working directory, as every caller holds
# it, even when DIR names another directory: one that exists from a
# subdirectory of the checkout is made absolute first. A path spelled through a
# symbolic link is retried in its physical form, and a Git Bash /c/… path in
# git's C:/… form. A path under no root keeps its spelling when it names
# nothing: cygpath would place a POSIX one under the Git installation.
dagents_name() {
  local file=${1//\\//} given physical
  dagents_stores_init "${2:-}"
  case $file in
    /*|[A-Za-z]:/*) ;;
    *)
      if [ -n "$_DAGENTS_TOP" ] && [ "$PWD" != "$_DAGENTS_TOP" ] && [ -e "$file" ]; then
        file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
      else
        printf '%s\n' "${file#./}"; return 0
      fi ;;
  esac
  given=$file
  if command -v cygpath >/dev/null 2>&1; then
    file=$(cygpath -m "$file" 2>/dev/null || printf '%s' "$file")
    _dagents_name_of "$file" && return 0
    file=$(_dagents_long "$file")
  fi
  _dagents_name_of "$file" && return 0
  physical="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)/$(basename "$file")"
  [ "$physical" != "/$(basename "$file")" ] && physical=$(_dagents_path "$physical")
  [ "$physical" != "/$(basename "$file")" ] && [ "$physical" != "$file" ] && _dagents_name_of "$physical" && return 0
  if [ -e "$file" ]; then printf '%s\n' "$file"; else printf '%s\n' "$given"; fi
}
