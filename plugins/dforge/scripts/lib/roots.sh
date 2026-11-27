# Sourced. Where a repository's two dforge families live (darkmem store
# options spec §2): documents (the docs directory) and progress (plan ledgers,
# their handoff.md, and the handoff files), each in the checkout or in the
# darkmem mirror, as `darkmem-config.mjs --mode` resolves them. Defines
# functions only.
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
_DFORGE_PROGRESS_STORE="" _DFORGE_LEDGER_ROOT="" _DFORGE_HANDOFF_DIR="" _DFORGE_PROJECT=""

# Node prints native paths; Git Bash compares them in git's C:/… form, which
# is always long: git expands an 8.3 short name such as RUNNER~1 in a TEMP
# directory that cygpath keeps.
_dforge_path() {
  if command -v cygpath >/dev/null 2>&1; then _dforge_long "$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")"
  else printf '%s\n' "$1"; fi
}

# The long form of a C:/… path. GetLongPathName, behind cygpath -l, needs the
# path to exist, so the deepest existing ancestor is expanded and the rest kept.
_dforge_long() {
  local head=$1 tail=""
  while [ -n "$head" ] && [ ! -e "$head" ]; do
    case $head in */*) tail="/${head##*/}$tail" head=${head%/*} ;; *) head="" ;; esac
  done
  if [ -n "$head" ]; then printf '%s%s\n' "$(cygpath -m -l "$head" 2>/dev/null || printf '%s' "$head")" "$tail"
  else printf '%s\n' "$1"; fi
}

# dforge_darkmem_possible — status 0 when this home could put a family in
# darkmem: its config.json has a darkmem section, or stores.json records a
# family already applied. Without either, darkmem-config.mjs --mode answers
# local for both families, so the callers skip its node start: the common case
# of a home that never used darkmem.
dforge_darkmem_possible() {
  [ -n "${HOME:-}" ] || return 0
  grep -qs '"darkmem"[[:space:]]*:' "$HOME/.dforge/config.json" || [ -f "$HOME/.dforge/stores.json" ]
}

# Both families local, computed without node: no git repository (then DIR
# stands in for the checkout), a home that never used darkmem, or no node on
# PATH while stores.json applies no darkmem store to this checkout (one that
# does exits 2: its documents or ledger are in the mirror, and a local root
# would split the plan's state).
_dforge_local() { # DIR TOP
  local base=${2:-$1}
  _DFORGE_DOCS_STORE=local
  _DFORGE_DOCS_ROOT=$(dforge_dir docs "$base")
  _DFORGE_PROGRESS_STORE=local
  _DFORGE_LEDGER_ROOT="$(dforge_dir state "$base")/sdd"
  _DFORGE_HANDOFF_DIR="$(dforge_dir state "$base")/handoff"
  _DFORGE_PROJECT=""
}

# _dforge_applied_darkmem TOP — stores.json records documents or progress as
# darkmem for TOP's primary checkout; without jq, for any checkout. A file that
# does not parse may record either, so it counts as applied, said on stderr.
_dforge_applied_darkmem() {
  local stores="${HOME:-}/.dforge/stores.json" common primary=$1
  [ -n "${HOME:-}" ] && [ -f "$stores" ] || return 1
  if ! command -v jq >/dev/null 2>&1; then
    grep -q '"darkmem"' "$stores"
    return
  fi
  if common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || primary=$1
  fi
  # Every file that parses gives true or false, so exit 4 (no result) is an
  # empty file, which may have held either.
  jq -e --arg k "$primary" '(.[$k] | objects | .documents == "darkmem" or .progress == "darkmem") // false' \
    < "$stores" >/dev/null 2>&1
  case $? in
    0) return 0 ;;
    1) return 1 ;;
    *) printf 'roots.sh: %s does not parse, so darkmem stores may be applied\n' "$stores" >&2; return 0 ;;
  esac
}

dforge_stores_init() { # [DIR]
  local dir=${1:-$PWD} top key out kind store root extra
  # Git Bash's $PWD is /tmp/... or /d/...; under MSYS_NO_PATHCONV git.exe takes
  # that form verbatim and finds no repository.
  top=$(git -C "$(dr_native_path "$dir")" rev-parse --show-toplevel 2>/dev/null) || top=""
  key="${HOME:-}|${top:-nogit:$dir}"
  [ "$_DFORGE_KEY" = "$key" ] && return 0
  _DFORGE_TOP=$top
  if [ -z "$top" ] || ! dforge_darkmem_possible; then
    _dforge_local "$dir" "$top"
    _DFORGE_KEY=$key
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    if _dforge_applied_darkmem "$top"; then
      printf 'roots.sh: node is required while darkmem stores are applied\n' >&2
      exit 2
    fi
    _dforge_local "$dir" "$top"
    _DFORGE_KEY=$key
    return 0
  fi
  if ! out=$(cd "$dir" && node "$(dr_native_path "$_ROOTS_LIB_DIR/darkmem-config.mjs")" --mode 2>&1); then
    printf '%s\n' "$out" >&2
    exit 2
  fi
  _DFORGE_DOCS_STORE="" _DFORGE_DOCS_ROOT="" _DFORGE_PROGRESS_STORE="" _DFORGE_LEDGER_ROOT="" _DFORGE_HANDOFF_DIR="" _DFORGE_PROJECT=""
  while IFS=$'\t' read -r kind store root extra; do
    case $kind in
      documents) _DFORGE_DOCS_STORE=$store _DFORGE_DOCS_ROOT=$(_dforge_path "$root") ;;
      progress)
        _DFORGE_PROGRESS_STORE=$store _DFORGE_LEDGER_ROOT=$(_dforge_path "$root")
        _DFORGE_HANDOFF_DIR=$(_dforge_path "$extra")
        ;;
      project) _DFORGE_PROJECT=$store ;;
    esac
  done <<<"$out"
  # A run that exits 0 without both lines (node's main-module check fails when
  # the plugin path holds a symbolic link) would leave every root empty, and
  # the helpers would print paths under /.
  if [ -z "$_DFORGE_DOCS_STORE" ] || [ -z "$_DFORGE_DOCS_ROOT" ] || [ -z "$_DFORGE_PROGRESS_STORE" ] \
     || [ -z "$_DFORGE_LEDGER_ROOT" ] || [ -z "$_DFORGE_HANDOFF_DIR" ]; then
    printf 'roots.sh: darkmem-config.mjs --mode printed no roots for %s\n' "$dir" >&2
    exit 2
  fi
  _DFORGE_KEY=$key
}

dforge_docs_root() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_DOCS_ROOT"; }
dforge_docs_store() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_DOCS_STORE"; }
dforge_progress_store() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_PROGRESS_STORE"; }
dforge_ledger_root() { dforge_stores_init "${1:-}"; printf '%s\n' "$_DFORGE_LEDGER_ROOT"; }
dforge_ledger_dir() { dforge_stores_init "${2:-}"; printf '%s/%s\n' "$_DFORGE_LEDGER_ROOT" "$1"; } # SLUG [DIR]

# dforge_project [DIR] — the darkmem project the repository is mapped to;
# status 1 with nothing printed when it is unmapped, outside git or without node.
dforge_project() { dforge_stores_init "${1:-}"; [ -n "$_DFORGE_PROJECT" ] || return 1; printf '%s\n' "$_DFORGE_PROJECT"; }

dforge_workspace() { # SLUG [DIR]
  dforge_stores_init "${2:-}"
  printf '%s/sdd/%s\n' "$(dforge_dir state "${_DFORGE_TOP:-${2:-$PWD}}")" "$1"
}

# dforge_handoff_file KEY [DIR] — the handoff file of KEY for DIR's checkout:
# in the darkmem mirror for the primary while progress is kept there (the
# mirror's work/handoff), otherwise under the checkout's state directory.
# Exit 2 for a key that is no plain file name, or is latest.
dforge_handoff_file() {
  local key=$1
  if ! _dforge_handoff_key "$key"; then
    printf 'handoff: invalid key %s\n' "$key" >&2
    return 2
  fi
  dforge_stores_init "${2:-}"
  printf '%s/%s.md\n' "$_DFORGE_HANDOFF_DIR" "$key"
}

# _dforge_handoff_key KEY — status 0 when KEY can name a handoff file. A file
# whose name is no key (an older layout's, which dforge-migrate renames) is
# not a handoff.
_dforge_handoff_key() { [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] && [ "$1" != latest ]; }
_dforge_handoff_listed() { local key=${1##*/}; [ -f "$1" ] && _dforge_handoff_key "${key%.md}"; }

# dforge_handoff_key_check KIND KEY — exit 2 when KEY cannot name a handoff of
# KIND: a plan or draft key that starts adhoc- or is latest, or an adhoc key
# that is neither adhoc-<8 hex digits> nor adhoc-legacy-*.
dforge_handoff_key_check() {
  case $1 in
    plan | draft) case $2 in adhoc-* | latest) return 2 ;; esac ;;
    adhoc) [[ $2 =~ ^adhoc-[0-9a-f]{8}$ || $2 =~ ^adhoc-legacy-[A-Za-z0-9._-]+$ ]] || return 2 ;;
    *) return 2 ;;
  esac
  return 0
}

# dforge_handoff_files [DIR] — every handoff/*.md of every checkout, in `git
# worktree list` order, then the mirror's while progress is darkmem; never the
# claims/ or notes/ contents, nor a file whose name is no handoff key.
dforge_handoff_files() {
  local wt f mirror=""
  dforge_stores_init "${1:-}"
  # From a linked worktree the handoff directory is local; the ledger root is the mirror's.
  [ "$_DFORGE_PROGRESS_STORE" = darkmem ] && mirror="${_DFORGE_LEDGER_ROOT%/*}/handoff"
  if [ -n "$_DFORGE_TOP" ]; then
    git -C "$(dr_native_path "$_DFORGE_TOP")" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
    while IFS= read -r wt; do
      wt=$(_dforge_path "$wt")
      [ -d "$wt" ] || continue
      for f in "$(dforge_dir state "$wt")"/handoff/*.md; do
        _dforge_handoff_listed "$f" && printf '%s\n' "$f"
      done
    done
  fi
  if [ -n "$mirror" ]; then
    for f in "$mirror"/*.md; do
      _dforge_handoff_listed "$f" && printf '%s\n' "$f"
    done
  fi
  return 0
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

# dforge_name_key NAME — the one name every docs prefix shares (store options
# spec §7.1): docs/superpowers/<rest> (before 3.0) and docs/forge/<rest> (3.x)
# are docs/dforge/<rest>. dforge has written only docs/dforge since 4.0.0, but
# plans, specs, ledgers and registers written before it cite an old prefix and
# are never rewritten, so every comparison of two document names compares
# their keys.
dforge_name_key() {
  local name=${1#./}
  [ "$name" = / ] || name=${name%/}
  case $name in
    docs/superpowers|docs/forge) printf 'docs/dforge\n' ;;
    docs/superpowers/*) printf 'docs/dforge/%s\n' "${name#docs/superpowers/}" ;;
    docs/forge/*) printf 'docs/dforge/%s\n' "${name#docs/forge/}" ;;
    *) printf '%s\n' "$name" ;;
  esac
}

# dforge_name_spellings NAME — the key, then for a document name the same name
# under the 3.x docs/forge and the pre-3.0 docs/superpowers. completed.md and
# register cells keep the spelling they were written with, so a search runs
# once per line and accepts any.
dforge_name_spellings() {
  local key rest
  key=$(dforge_name_key "$1")
  printf '%s\n' "$key"
  case $key in
    docs/dforge) printf 'docs/forge\ndocs/superpowers\n' ;;
    docs/dforge/*)
      rest=${key#docs/dforge/}
      printf 'docs/forge/%s\ndocs/superpowers/%s\n' "$rest" "$rest" ;;
  esac
}

# dforge_resolve NAME [DIR] — a document name under the docs root, any other
# relative name under the worktree, an absolute path unchanged. A historical
# citation docs/superpowers/… or docs/forge/… resolves as docs/dforge/… does.
dforge_resolve() {
  local name=${1#./}
  dforge_stores_init "${2:-}"
  case $name in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) printf '%s\n' "$1" ;;
    docs/dforge|docs/forge|docs/superpowers) printf '%s\n' "$_DFORGE_DOCS_ROOT" ;;
    docs/dforge/*) printf '%s/%s\n' "$_DFORGE_DOCS_ROOT" "${name#docs/dforge/}" ;;
    docs/forge/*) printf '%s/%s\n' "$_DFORGE_DOCS_ROOT" "${name#docs/forge/}" ;;
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
# A relative FILE is a path from the working directory, as every caller holds
# it, even when DIR names another directory: one that exists from a
# subdirectory of the checkout is made absolute first. A path spelled through a
# symbolic link is retried in its physical form, and a Git Bash /c/… path in
# git's C:/… form. A path under no root keeps its spelling when it names
# nothing: cygpath would place a POSIX one under the Git installation.
dforge_name() {
  local file=${1//\\//} given physical
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
  given=$file
  if command -v cygpath >/dev/null 2>&1; then
    file=$(cygpath -m "$file" 2>/dev/null || printf '%s' "$file")
    _dforge_name_of "$file" && return 0
    file=$(_dforge_long "$file")
  fi
  _dforge_name_of "$file" && return 0
  physical="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)/$(basename "$file")"
  [ "$physical" != "/$(basename "$file")" ] && physical=$(_dforge_path "$physical")
  [ "$physical" != "/$(basename "$file")" ] && [ "$physical" != "$file" ] && _dforge_name_of "$physical" && return 0
  if [ -e "$file" ]; then printf '%s\n' "$file"; else printf '%s\n' "$given"; fi
}
