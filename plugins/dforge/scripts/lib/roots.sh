# Sourced. Where a repository's two dforge families live (darkmem store
# options spec §2): documents (the docs directory) and progress (plan ledgers,
# their handoff.md, and latest.md), each in the checkout or in the darkmem
# mirror, as `darkmem-config.mjs --mode` resolves them. Defines functions only.
#
# Every helper takes an optional trailing DIR naming the checkout (default: the
# working directory). The resolution is cached per HOME and checkout in shell
# variables; a helper called inside $(…) cannot fill the caller's cache, so a
# script that calls helpers repeatedly calls dforge_stores_init in its main
# shell first. A ConfigError exits the script with status 2.

. "$(dirname "${BASH_SOURCE[0]}")/dforge-dir.sh"
. "$(dirname "${BASH_SOURCE[0]}")/native-path.sh"
_ROOTS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

_DFORGE_KEY="" _DFORGE_TOP="" _DFORGE_DOCS_STORE="" _DFORGE_DOCS_ROOT=""
_DFORGE_PROGRESS_STORE="" _DFORGE_LEDGER_ROOT="" _DFORGE_LATEST="" _DFORGE_PROJECT=""

# Node prints native paths; Git Bash compares them in git's C:/… form.
_dforge_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"
  else printf '%s\n' "$1"; fi
}

# Both families local, computed without node: no node on PATH, or no git
# repository (then DIR stands in for the checkout).
_dforge_local() { # DIR TOP
  local base=${2:-$1} primary=${2:-$1} common
  if [ -n "$2" ]; then
    if common=$(git -C "$2" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
      primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || primary=$2
    fi
  fi
  _DFORGE_DOCS_STORE=local
  _DFORGE_DOCS_ROOT=$(dforge_dir docs "$base")
  _DFORGE_PROGRESS_STORE=local
  _DFORGE_LEDGER_ROOT="$(dforge_dir state "$base")/sdd"
  _DFORGE_LATEST="$(dforge_dir state "$primary")/handoff/latest.md"
  _DFORGE_PROJECT=""
}

dforge_stores_init() { # [DIR]
  local dir=${1:-$PWD} top key out kind store root extra
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=""
  key="${HOME:-}|${top:-nogit:$dir}"
  [ "$_DFORGE_KEY" = "$key" ] && return 0
  _DFORGE_TOP=$top
  if [ -z "$top" ] || ! command -v node >/dev/null 2>&1; then
    _dforge_local "$dir" "$top"
    _DFORGE_KEY=$key
    return 0
  fi
  if ! out=$(cd "$dir" && node "$(dr_native_path "$_ROOTS_LIB_DIR/darkmem-config.mjs")" --mode 2>&1); then
    printf '%s\n' "$out" >&2
    exit 2
  fi
  _DFORGE_DOCS_STORE="" _DFORGE_DOCS_ROOT="" _DFORGE_PROGRESS_STORE="" _DFORGE_LEDGER_ROOT="" _DFORGE_LATEST="" _DFORGE_PROJECT=""
  while IFS=$'\t' read -r kind store root extra; do
    case $kind in
      documents) _DFORGE_DOCS_STORE=$store _DFORGE_DOCS_ROOT=$(_dforge_path "$root") ;;
      progress)
        _DFORGE_PROGRESS_STORE=$store _DFORGE_LEDGER_ROOT=$(_dforge_path "$root")
        _DFORGE_LATEST=$(_dforge_path "$extra")
        ;;
      project) _DFORGE_PROJECT=$store ;;
    esac
  done <<<"$out"
  # A run that exits 0 without both lines (node's main-module check fails when
  # the plugin path holds a symbolic link) would leave every root empty, and
  # the helpers would print paths under /.
  if [ -z "$_DFORGE_DOCS_STORE" ] || [ -z "$_DFORGE_DOCS_ROOT" ] || [ -z "$_DFORGE_PROGRESS_STORE" ] \
     || [ -z "$_DFORGE_LEDGER_ROOT" ] || [ -z "$_DFORGE_LATEST" ]; then
    printf 'roots.sh: darkmem-config.mjs --mode printed no roots for %s\n' "$dir" >&2
    exit 2
  fi
  _DFORGE_KEY=$key
}

dforge_docs_root() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_DOCS_ROOT"; }
dforge_docs_store() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_DOCS_STORE"; }
dforge_progress_store() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_PROGRESS_STORE"; }
dforge_ledger_root() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_LEDGER_ROOT"; }
dforge_latest_file() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_LATEST"; }
dforge_ledger_dir() { dforge_stores_init "${2:-}"; printf '%s/%s\n' "$_DFORGE_LEDGER_ROOT" "$1"; } # SLUG [DIR]

# dforge_project [DIR] — the darkmem project the repository is mapped to;
# status 1 with nothing printed when it is unmapped, outside git or without node.
dforge_project() { dforge_stores_init "${1:-}"; [ -n "$_DFORGE_PROJECT" ] || return 1; printf '%s\n' "$_DFORGE_PROJECT"; }

dforge_workspace() { # SLUG [DIR]
  dforge_stores_init "${2:-}"
  printf '%s/sdd/%s\n' "$(dforge_dir state "${_DFORGE_TOP:-${2:-$PWD}}")" "$1"
}

# dforge_ledger_files [DIR] — "<ledger>\t<checkout>" for every worktree's
# ledgers when progress is local; "<ledger>\tmirror" for the mirror's when it
# is darkmem, listed once, since every worktree shares the mirror.
dforge_ledger_files() {
  local wt f
  dforge_stores_init "${1:-}"
  if [ "$_DFORGE_PROGRESS_STORE" = darkmem ]; then
    for f in "$_DFORGE_LEDGER_ROOT"/*/progress.md; do
      [ -f "$f" ] && printf '%s\tmirror\n' "$f"
    done
    return 0
  fi
  [ -n "$_DFORGE_TOP" ] || return 0
  git -C "$_DFORGE_TOP" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    for f in "$(dforge_dir state "$wt")"/sdd/*/progress.md; do
      [ -f "$f" ] && printf '%s\t%s\n' "$f" "$wt"
    done
  done
  return 0
}

# dforge_name_key NAME — the one name both docs prefixes share (store options
# spec §7.1): docs/superpowers/<rest> is docs/dforge/<rest>. dforge has
# written only docs/dforge since 3.0.0, but plans, specs, ledgers and registers
# written before it cite the old prefix and are never rewritten, so every
# comparison of two document names compares their keys.
dforge_name_key() {
  local name=${1#./}
  case $name in
    docs/superpowers) printf 'docs/dforge\n' ;;
    docs/superpowers/*) printf 'docs/dforge/%s\n' "${name#docs/superpowers/}" ;;
    *) printf '%s\n' "$name" ;;
  esac
}

# dforge_name_spellings NAME — the key, then for a document name the same name
# under the pre-3.0 docs/superpowers. completed.md and register cells keep the
# spelling they were written with, so a search runs once per line and accepts
# either.
dforge_name_spellings() {
  local key
  key=$(dforge_name_key "$1")
  printf '%s\n' "$key"
  case $key in
    docs/dforge) printf 'docs/superpowers\n' ;;
    docs/dforge/*) printf 'docs/superpowers/%s\n' "${key#docs/dforge/}" ;;
  esac
}

# dforge_resolve NAME [DIR] — a document name under the docs root, any other
# relative name under the worktree, an absolute path unchanged. A historical
# citation docs/superpowers/… resolves as docs/dforge/… does.
dforge_resolve() {
  local name=${1#./}
  dforge_stores_init "${2:-}"
  case $name in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) printf '%s\n' "$1" ;;
    docs/dforge|docs/superpowers) printf '%s\n' "$_DFORGE_DOCS_ROOT" ;;
    docs/dforge/*) printf '%s/%s\n' "$_DFORGE_DOCS_ROOT" "${name#docs/dforge/}" ;;
    docs/superpowers/*) printf '%s/%s\n' "$_DFORGE_DOCS_ROOT" "${name#docs/superpowers/}" ;;
    *) printf '%s/%s\n' "${_DFORGE_TOP:-${2:-$PWD}}" "$name" ;;
  esac
}

_dforge_name_of() { # ABSOLUTE — its name when it lies under a root; status 1 otherwise
  local docs_name
  docs_name=$(dforge_dir_rel docs "${_DFORGE_TOP:-$PWD}")
  case $1 in
    "$_DFORGE_DOCS_ROOT") printf '%s\n' "$docs_name"; return 0 ;;
    "$_DFORGE_DOCS_ROOT"/*) printf '%s/%s\n' "$docs_name" "${1#"$_DFORGE_DOCS_ROOT"/}"; return 0 ;;
  esac
  [ -n "$_DFORGE_TOP" ] || return 1
  case $1 in "$_DFORGE_TOP"/*) printf '%s\n' "${1#"$_DFORGE_TOP"/}"; return 0 ;; esac
  return 1
}

# dforge_name FILE [DIR] — the inverse of dforge_resolve, computed from the roots.
# A relative FILE that exists from a subdirectory of the checkout is made
# absolute first; a path spelled through a symbolic link is retried in its
# physical form, and a Git Bash /c/… path in git's C:/… form.
dforge_name() {
  local file=${1//\\//} physical
  dforge_stores_init "${2:-}"
  case $file in
    /*|[A-Za-z]:/*) ;;
    *)
      if [ -n "$_DFORGE_TOP" ] && [ "$PWD" != "$_DFORGE_TOP" ] && [ -e "$file" ]; then
        file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
      else
        printf '%s\n' "${file#./}"; return 0
      fi ;;
  esac
  if command -v cygpath >/dev/null 2>&1; then file=$(cygpath -m "$file" 2>/dev/null || printf '%s' "$file"); fi
  _dforge_name_of "$file" && return 0
  physical="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)/$(basename "$file")"
  [ "$physical" != "/$(basename "$file")" ] && [ "$physical" != "$file" ] && _dforge_name_of "$physical" && return 0
  printf '%s\n' "$file"
}
