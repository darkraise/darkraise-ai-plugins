# shellcheck shell=bash
# ending_released MESSAGE STAMP LATEST — whether a stop message ends on the
# next-step block this turn wrote, which releases a held turn. Status 0 when
# LATEST is newer than STAMP and MESSAGE contains LATEST's `**Next:**` line
# (the text after `**Next:** `, verbatim); or when MESSAGE has a line reading
# exactly `## Next session` and LATEST cannot be written (next-step then
# prints the block and exits 4): it exists and is not writable, or it is absent
# and its nearest existing parent directory is not writable. Status 1
# otherwise. A hand-typed block passes neither test. Only grep and awk run.
ending_released() {
  local message=$1 stamp=$2 latest=$3 next dir parent
  if [ -f "$latest" ] && [ "$latest" -nt "$stamp" ]; then
    next=$(awk '{ sub(/\r$/, "") } $0 == "## Next session" { in_block = 1; next } in_block && /^## / { exit } in_block && index($0, "**Next:** ") == 1 { print substr($0, 11); exit }' "$latest")
    [ -n "$next" ] && grep -qF -- "$next" <<<"$message" && return 0
  fi
  awk '{ sub(/\r$/, "") } $0 == "## Next session" { found = 1; exit } END { exit !found }' <<<"$message" || return 1
  if [ -e "$latest" ]; then
    [ ! -w "$latest" ]
    return
  fi
  dir=${latest%/*}
  [ "$dir" != "$latest" ] || dir=.
  while [ ! -d "$dir" ]; do
    parent=${dir%/*}
    if [ "$parent" = "$dir" ]; then dir=.; break; fi
    dir=${parent:-/}
  done
  [ ! -w "$dir" ]
}
