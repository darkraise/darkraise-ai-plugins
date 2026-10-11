# Sourced. A repository's dr-forge directories: .forge/ and docs/forge/, unless
# only the pre-2.0 .superpowers/ or docs/superpowers/ exists, which stays in use
# so a checkout from before dr-forge 2.0.0 keeps its ledgers, handoffs and docs.

# forge_dir state|docs [ROOT] — the directory under ROOT (default: .).
forge_dir() {
  local root=${2:-.} new old
  case ${1:-} in
    state) new=.forge old=.superpowers ;;
    docs) new=docs/forge old=docs/superpowers ;;
    *) printf 'forge_dir: unknown kind %s (state or docs)\n' "${1:-}" >&2; return 2 ;;
  esac
  if [ ! -e "$root/$new" ] && [ -e "$root/$old" ]; then
    printf '%s/%s\n' "$root" "$old"
  else
    printf '%s/%s\n' "$root" "$new"
  fi
}

# forge_dir_rel state|docs [ROOT] — the same directory, relative to ROOT.
forge_dir_rel() {
  local dir
  dir=$(forge_dir "$@") || return
  printf '%s\n' "${dir#"${2:-.}"/}"
}
