# Sourced. The ui-ux skill's shared parsing: which files are UI files, the
# fingerprint of their contents, the project UI profile, a spec's UI/UX
# contract and a proof report's rows. Globs are bash case patterns matched
# against repository-relative paths, so * crosses /.
declare -F plan_header >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/plan.sh"

UIUX_DEFAULT_GLOBS='*.tsx *.jsx *.vue *.svelte *.astro *.html *.css *.scss *.sass *.less *.xaml *.axaml *.rc *.Designer.cs *.razor *.cshtml *res/layout/*.xml *res/values/*.xml *res/drawable/*.xml *.ui *.qml *.glade *.blp'
UIUX_EXCLUDE_GLOBS='*.test.* *.spec.* *.stories.*'

# uiux_profile ROOT — ROOT's UI profile path, whether or not it exists.
uiux_profile() { printf '%s/ui-ux/profile.md\n' "$(dforge_docs_root "$1")"; }

# uiux_proofs_dir ROOT — where ROOT's proof reports live.
uiux_proofs_dir() { printf '%s/ui-ux/proofs\n' "$(dforge_docs_root "$1")"; }

# uiux_field FILE LABEL — the value of FILE's first "**LABEL:**" line outside
# fences, trimmed, backticks removed; nothing when there is none.
uiux_field() {
  tr -d '\r' < "$1" | awk -v p="**$2:**" "$_PLAN_AWK"'
    stop { next }
    in_fence($0) { next }
    index($0, p) == 1 {
      v = substr($0, length(p) + 1); gsub(/`/, "", v)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      print v; stop = 1
    }
  '
}

# uiux_globs ROOT — the effective UI globs, one per line: the profile's
# "**UI paths:**" value when it has one, else the platform defaults.
uiux_globs() {
  local profile line=""
  profile=$(uiux_profile "$1")
  [ ! -f "$profile" ] || line=$(uiux_field "$profile" "UI paths")
  [ -n "$line" ] || line=$UIUX_DEFAULT_GLOBS
  tr ' \t,' '\n\n\n' <<<"$line" | grep -v '^$'
}

# uiux_is_ui PATH GLOBS — status 0 when PATH matches one of GLOBS (one per
# line) and none of the exclusions.
uiux_is_ui() {
  local path=$1 glob
  set -f
  for glob in $UIUX_EXCLUDE_GLOBS; do
    # shellcheck disable=SC2254
    case $path in $glob) set +f; return 1 ;; esac
  done
  set +f
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2254
    case $path in $glob) return 0 ;; esac
  done <<<"$2"
  return 1
}

# uiux_filter ROOT — the UI paths among the repository-relative paths on stdin.
uiux_filter() {
  local globs path
  globs=$(uiux_globs "$1")
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if uiux_is_ui "$path" "$globs"; then printf '%s\n' "$path"; fi
  done
  return 0
}

# uiux_files ROOT — every UI file in ROOT's working tree, tracked or
# untracked but not ignored, sorted; a tracked file deleted from the tree is
# left out.
uiux_files() {
  local path
  git -C "$1" -c core.quotePath=false ls-files -co --exclude-standard 2>/dev/null | LC_ALL=C sort -u | uiux_filter "$1" |
    while IFS= read -r path; do
      if [ -f "$1/$path" ]; then printf '%s\n' "$path"; fi
    done
  return 0
}

# uiux_changed ROOT BASE — the UI files that differ between BASE and the
# working tree, committed or not, deleted ones included, plus untracked ones.
uiux_changed() {
  { git -C "$1" -c core.quotePath=false diff --name-only "$2" -- 2>/dev/null
    git -C "$1" -c core.quotePath=false ls-files -o --exclude-standard 2>/dev/null; } | LC_ALL=C sort -u | uiux_filter "$1"
}

# uiux_fingerprint ROOT — 16 hex digits naming the paths and contents of every
# UI file, or "none" when there is none. Git does the hashing.
uiux_fingerprint() {
  local files hashes
  files=$(uiux_files "$1")
  if [ -z "$files" ]; then echo none; return 0; fi
  hashes=$(cd "$1" && printf '%s\n' "$files" | git hash-object --stdin-paths) || return 1
  paste <(printf '%s\n' "$files") <(printf '%s\n' "$hashes") | git -C "$1" hash-object --stdin | cut -c1-16
}

# uiux_section FILE HEADING — FILE's "## HEADING" section up to the next "## "
# heading, fenced lines included; a "## " line inside a fence does not end it.
uiux_section() {
  tr -d '\r' < "$1" | awk -v h="## $2" "$_PLAN_AWK"'
    in_fence($0) { if (on) print; next }
    /^## / { t = $0; sub(/[ \t]+$/, "", t); on = (t == h); next }
    on { print }
  '
}

# uiux_ids — the item IDs the text on stdin defines, in order, unique: a
# "- **ID**" bullet or a "| ID |" table row at column 0, outside fences.
uiux_ids() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    match($0, /^- \*\*(UI|UX|OP)-[0-9]+\*\*/) {
      id = substr($0, 5, RLENGTH - 6); if (!seen[id]++) print id; next
    }
    match($0, /^\|[ \t]*(UI|UX|OP)-[0-9]+[ \t]*\|/) {
      id = substr($0, RSTART, RLENGTH); gsub(/[| \t]/, "", id); if (!seen[id]++) print id
    }
  '
}

# uiux_contract_ids SPEC — the IDs the spec's "## UI/UX contract" defines.
uiux_contract_ids() { uiux_section "$1" "UI/UX contract" | uiux_ids; }

# uiux_items FILE SECTION ID... — each ID's definition in FILE's section,
# verbatim, in the order given, each followed by a blank line: a bullet with
# its continuation lines (indented by two spaces or a tab), or a table row
# under its table's header and separator rows.
uiux_items() {
  local file=$1 section=$2 text id
  shift 2
  text=$(uiux_section "$file" "$section")
  for id in "$@"; do
    awk -v id="$id" "$_PLAN_AWK"'
      in_fence($0) { if (on) print; next }
      on && /^(  |\t)/ { print; next }
      on { on = 0 }
      /^\|/ { if (!intable) { head = $0; sepl = ""; rows = 0; intable = 1 } rows++; if (rows == 2) sepl = $0 }
      !/^\|/ { intable = 0 }
      index($0, "- **" id "**") == 1 { print; on = 1; next }
      match($0, /^\|[ \t]*(UI|UX|OP)-[0-9]+[ \t]*\|/) {
        c = substr($0, RSTART, RLENGTH); gsub(/[| \t]/, "", c)
        if (c == id) { print head; print sepl; print }
      }
    ' <<<"$text"
    echo
  done
}

# uiux_rows REPORT — one "ID\037verdict\037evidence\037note" line per row of
# the report's "## Results" table whose first cell is an ID.
uiux_rows() {
  uiux_section "$1" Results | awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^\|/ {
      n = split($0, c, "|")
      id = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id !~ /^(UI|UX|OP)-[0-9]+$/) next
      for (i = 3; i <= 5; i++) { v[i] = (i < n ? c[i] : ""); gsub(/^[ \t]+|[ \t]+$/, "", v[i]) }
      printf "%s\037%s\037%s\037%s\n", id, tolower(v[3]), v[4], v[5]
    }
  '
}

# uiux_ran_skill TRANSCRIPT — status 0 when the transcript shows a Skill tool
# call for dforge:ui-ux (or ui-ux) or a typed /dforge:ui-ux command.
uiux_ran_skill() {
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  jq -rR 'fromjson? | objects
    | if .type? == "assistant" then
        .message.content? | arrays | .[] | select(.type? == "tool_use" and .name? == "Skill")
        | .input.skill? | strings | select(. == "dforge:ui-ux" or . == "ui-ux")
      elif .type? == "user" then
        .message.content? | (if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text?) else empty end)
        | strings | select(contains("<command-name>/dforge:ui-ux"))
      else empty end' "$1" 2>/dev/null | grep -q .
}
