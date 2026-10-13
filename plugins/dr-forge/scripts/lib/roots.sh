# Sourced. Where a repository's two dr-forge families live (darkmem store
# options spec §2): documents (the docs directory) and progress (plan ledgers,
# their handoff.md, and latest.md), each in the checkout or in the darkmem
# mirror, as `darkmem-config.mjs --mode` resolves them. Defines functions only.
#
# Every helper takes an optional trailing DIR naming the checkout (default: the
# working directory). The resolution is cached per HOME and checkout in shell
# variables; a helper called inside $(…) cannot fill the caller's cache, so a
# script that calls helpers repeatedly calls forge_stores_init in its main
# shell first. A ConfigError exits the script with status 2.

. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"
. "$(dirname "${BASH_SOURCE[0]}")/native-path.sh"
_ROOTS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

_FORGE_KEY="" _FORGE_TOP="" _FORGE_DOCS_STORE="" _FORGE_DOCS_ROOT=""
_FORGE_PROGRESS_STORE="" _FORGE_LEDGER_ROOT="" _FORGE_LATEST=""

# Node prints native paths; Git Bash compares them in git's C:/… form.
_forge_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"
  else printf '%s\n' "$1"; fi
}

# Both families local, computed without node: no node on PATH, or no git
# repository (then DIR stands in for the checkout).
_forge_local() { # DIR TOP
  local base=${2:-$1} primary=${2:-$1} common
  if [ -n "$2" ]; then
    if common=$(git -C "$2" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
      primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || primary=$2
    fi
  fi
  _FORGE_DOCS_STORE=local
  _FORGE_DOCS_ROOT=$(forge_dir docs "$base")
  _FORGE_PROGRESS_STORE=local
  _FORGE_LEDGER_ROOT="$(forge_dir state "$base")/sdd"
  _FORGE_LATEST="$(forge_dir state "$primary")/handoff/latest.md"
}

forge_stores_init() { # [DIR]
  local dir=${1:-$PWD} top key out kind store root extra
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=""
  key="${HOME:-}|${top:-nogit:$dir}"
  [ "$_FORGE_KEY" = "$key" ] && return 0
  _FORGE_TOP=$top
  if [ -z "$top" ] || ! command -v node >/dev/null 2>&1; then
    _forge_local "$dir" "$top"
    _FORGE_KEY=$key
    return 0
  fi
  if ! out=$(cd "$dir" && node "$(dr_native_path "$_ROOTS_LIB_DIR/darkmem-config.mjs")" --mode 2>&1); then
    printf '%s\n' "$out" >&2
    exit 2
  fi
  _FORGE_DOCS_STORE="" _FORGE_DOCS_ROOT="" _FORGE_PROGRESS_STORE="" _FORGE_LEDGER_ROOT="" _FORGE_LATEST=""
  while IFS=$'\t' read -r kind store root extra; do
    case $kind in
      documents) _FORGE_DOCS_STORE=$store _FORGE_DOCS_ROOT=$(_forge_path "$root") ;;
      progress)
        _FORGE_PROGRESS_STORE=$store _FORGE_LEDGER_ROOT=$(_forge_path "$root")
        _FORGE_LATEST=$(_forge_path "$extra")
        ;;
    esac
  done <<<"$out"
  # A run that exits 0 without both lines (node's main-module check fails when
  # the plugin path holds a symbolic link) would leave every root empty, and
  # the helpers would print paths under /.
  if [ -z "$_FORGE_DOCS_STORE" ] || [ -z "$_FORGE_DOCS_ROOT" ] || [ -z "$_FORGE_PROGRESS_STORE" ] \
     || [ -z "$_FORGE_LEDGER_ROOT" ] || [ -z "$_FORGE_LATEST" ]; then
    printf 'roots.sh: darkmem-config.mjs --mode printed no roots for %s\n' "$dir" >&2
    exit 2
  fi
  _FORGE_KEY=$key
}

forge_docs_root() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_DOCS_ROOT"; }
forge_docs_store() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_DOCS_STORE"; }
forge_progress_store() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_PROGRESS_STORE"; }
forge_ledger_root() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_LEDGER_ROOT"; }
forge_latest_file() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_LATEST"; }
forge_ledger_dir() { forge_stores_init "${2:-}"; printf '%s/%s\n' "$_FORGE_LEDGER_ROOT" "$1"; } # SLUG [DIR]

forge_workspace() { # SLUG [DIR]
  forge_stores_init "${2:-}"
  printf '%s/sdd/%s\n' "$(forge_dir state "${_FORGE_TOP:-${2:-$PWD}}")" "$1"
}

# forge_ledger_files [DIR] — "<ledger>\t<checkout>" for every worktree's
# ledgers when progress is local; "<ledger>\tmirror" for the mirror's when it
# is darkmem, listed once, since every worktree shares the mirror.
forge_ledger_files() {
  local wt f
  forge_stores_init "${1:-}"
  if [ "$_FORGE_PROGRESS_STORE" = darkmem ]; then
    for f in "$_FORGE_LEDGER_ROOT"/*/progress.md; do
      [ -f "$f" ] && printf '%s\tmirror\n' "$f"
    done
    return 0
  fi
  [ -n "$_FORGE_TOP" ] || return 0
  git -C "$_FORGE_TOP" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    for f in "$(forge_dir state "$wt")"/sdd/*/progress.md; do
      [ -f "$f" ] && printf '%s\t%s\n' "$f" "$wt"
    done
  done
  return 0
}

# forge_resolve NAME [DIR] — a document name (docs/forge/… or the pre-2.0
# docs/superpowers/…) under the docs root, any other relative name under the
# worktree, an absolute path unchanged.
forge_resolve() {
  local name=${1#./}
  forge_stores_init "${2:-}"
  case $name in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) printf '%s\n' "$1" ;;
    docs/forge|docs/superpowers) printf '%s\n' "$_FORGE_DOCS_ROOT" ;;
    docs/forge/*) printf '%s/%s\n' "$_FORGE_DOCS_ROOT" "${name#docs/forge/}" ;;
    docs/superpowers/*) printf '%s/%s\n' "$_FORGE_DOCS_ROOT" "${name#docs/superpowers/}" ;;
    *) printf '%s/%s\n' "${_FORGE_TOP:-${2:-$PWD}}" "$name" ;;
  esac
}

_forge_name_of() { # ABSOLUTE — its name when it lies under a root; status 1 otherwise
  local docs_name
  docs_name=$(forge_dir_rel docs "${_FORGE_TOP:-$PWD}")
  case $1 in
    "$_FORGE_DOCS_ROOT") printf '%s\n' "$docs_name"; return 0 ;;
    "$_FORGE_DOCS_ROOT"/*) printf '%s/%s\n' "$docs_name" "${1#"$_FORGE_DOCS_ROOT"/}"; return 0 ;;
  esac
  [ -n "$_FORGE_TOP" ] || return 1
  case $1 in "$_FORGE_TOP"/*) printf '%s\n' "${1#"$_FORGE_TOP"/}"; return 0 ;; esac
  return 1
}

# forge_name FILE [DIR] — the inverse of forge_resolve, computed from the roots.
# A relative FILE that exists from a subdirectory of the checkout is made
# absolute first; a path spelled through a symbolic link is retried in its
# physical form, and a Git Bash /c/… path in git's C:/… form.
forge_name() {
  local file=${1//\\//} physical
  forge_stores_init "${2:-}"
  case $file in
    /*|[A-Za-z]:/*) ;;
    *)
      if [ -n "$_FORGE_TOP" ] && [ "$PWD" != "$_FORGE_TOP" ] && [ -e "$file" ]; then
        file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
      else
        printf '%s\n' "${file#./}"; return 0
      fi ;;
  esac
  if command -v cygpath >/dev/null 2>&1; then file=$(cygpath -m "$file" 2>/dev/null || printf '%s' "$file"); fi
  _forge_name_of "$file" && return 0
  physical="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)/$(basename "$file")"
  [ "$physical" != "/$(basename "$file")" ] && [ "$physical" != "$file" ] && _forge_name_of "$physical" && return 0
  printf '%s\n' "$file"
}
