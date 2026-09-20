# Item register parsing shared by register, next-step, plan-lint and repo-audit,
# so every reader agrees on what a row is. Sourced; defines functions only.

_REGISTER_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_REGISTER_LIB_DIR/plan.sh"

# The vocabulary is closed. Three states record a decision or a debt rather
# than progress, and carry a mandatory note: a ruling without its reason is
# what a findings file already fails to preserve.
REGISTER_STATES='open planned doing verify done deferred n/a'
REGISTER_UNRESOLVED='open planned doing verify'
REGISTER_NOTE_REQUIRED='verify deferred n/a'

# A cell may hold an escaped pipe. Every parse swaps \| for \001 before
# splitting and swaps it back after, so a note may contain one.
_REGISTER_AWK='
function reg_cells(line, f,   n, i) {
  gsub(/^[ \t]+|[ \t]+$/, "", line)
  if (substr(line, 1, 1) != "|") return 0
  gsub(/\\\|/, "\001", line)
  n = split(line, f, "|")
  for (i = 1; i <= n; i++) {
    gsub(/^[ \t]+|[ \t]+$/, "", f[i])
    gsub(/\001/, "|", f[i])
  }
  return n
}
'

# register_field FILE LABEL — the first "**LABEL:**" value outside fences.
register_field() {
  tr -d '\r' < "$1" | awk -v p="**$2:**" "$_PLAN_AWK"'
    stop { next }
    in_fence($0) { next }
    index($0, p) == 1 {
      v = substr($0, length(p) + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      print v
      stop = 1
    }
  '
  return 0
}

# register_scan FILE — every candidate row line outside fences, as
# "lineno<TAB>fieldcount<TAB>id<TAB>item<TAB>assigned<TAB>acceptance<TAB>state<TAB>note".
# The header and separator rows are dropped; everything else is reported so
# that `register check` can name a malformed row by its line.
register_scan() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK$_REGISTER_AWK"'
    in_fence($0) { next }
    {
      n = reg_cells($0, c)
      if (n == 0) next
      if (c[2] == "#" || c[2] ~ /^:?-+:?$/) next
      printf "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", NR, n, c[2], c[3], c[4], c[5], c[6], c[7]
    }
  '
  return 0
}

# register_rows FILE — the well-formed rows, as
# "id<TAB>item<TAB>assigned<TAB>acceptance<TAB>state<TAB>note".
register_rows() {
  register_scan "$1" | awk -F'\t' '$2 == 8 && $3 ~ /^[0-9]+$/ {
    print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8
  }'
  return 0
}

# register_open FILE — the rows whose state is unresolved.
register_open() {
  register_rows "$1" | awk -F'\t' -v u=" $REGISTER_UNRESOLVED " 'index(u, " " $5 " ") > 0'
  return 0
}

# register_covers FILE — one repository-relative spec path per line; nothing
# when the register covers no spec yet.
register_covers() {
  local value
  value=$(register_field "$1" Covers)
  [ -n "$value" ] && [ "$value" != "-" ] || return 0
  printf '%s' "$value" | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^`//' -e 's/`$//' \
    | grep -v '^$'
  return 0
}

# register_files ROOT — every register in the repository.
register_files() {
  local dir="$1/docs/superpowers/registers" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f"
  done
  return 0
}

# register_for_spec ROOT SPEC... — the registers covering any of the given
# specs. Resolution runs this way round so that a plan cannot carry a stale
# pointer to a register.
register_for_spec() {
  local root="$1" f cov want
  shift
  [ $# -gt 0 ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r cov; do
      [ -n "$cov" ] || continue
      cov=${cov#./}
      for want in "$@"; do
        want=${want#./}
        if [ "$cov" = "$want" ]; then
          printf '%s\n' "$f"
          break 2
        fi
      done
    done < <(register_covers "$f")
  done < <(register_files "$root")
  return 0
}
