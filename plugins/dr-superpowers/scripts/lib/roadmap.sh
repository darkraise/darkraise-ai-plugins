# Roadmap parsing shared by roadmap, next-step, repo-audit and the SessionStart
# hook, so every reader agrees on what a milestone is and when it is finished.
# Sourced; defines functions only.
#
# A milestone's progress is never stored. It is computed from the milestone's
# register (one row per epic) and from every register covering an epic's spec
# (one row per requirement); the only stored state is `closed`, written by
# `roadmap close` after an audit.

_ROADMAP_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_ROADMAP_LIB_DIR/register.sh"

ROADMAP_STATES='open closed'

# roadmap_file ROOT — the roadmap path, printed only when it exists.
roadmap_file() {
  local f="$1/docs/superpowers/roadmap.md"
  [ -f "$f" ] && printf '%s\n' "$f"
  return 0
}

# roadmap_scan FILE — every candidate milestone row outside fences, as
# "lineno<TAB>fieldcount<TAB>m<TAB>name<TAB>exit<TAB>register<TAB>state<TAB>note".
# Same cell grammar as a register; the header row's first cell is "M".
roadmap_scan() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK$_REGISTER_AWK"'
    in_fence($0) { next }
    {
      n = reg_cells($0, c)
      if (n == 0) next
      if (c[2] == "M" || c[2] ~ /^:?-+:?$/) next
      printf "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", NR, n, c[2], c[3], c[4], c[5], c[6], c[7]
    }
  '
  return 0
}

# roadmap_rows FILE — the well-formed milestones, in file order, as
# "m<TAB>name<TAB>exit<TAB>register<TAB>state<TAB>note". The register cell
# loses any surrounding backticks.
roadmap_rows() {
  roadmap_scan "$1" | awk -F'\t' '$2 == 8 && $3 ~ /^M[0-9]+$/ {
    r = $6; gsub(/^`|`$/, "", r)
    print $3 "\t" $4 "\t" $5 "\t" r "\t" $7 "\t" $8
  }'
  return 0
}

# roadmap_current FILE — the first open milestone's row; nothing when every
# milestone is closed.
roadmap_current() {
  roadmap_rows "$1" | awk -F'\t' '$5 != "closed" { print; exit }'
  return 0
}

# roadmap_row FILE M — one milestone's row.
roadmap_row() {
  roadmap_rows "$1" | awk -F'\t' -v m="$2" '$1 == m'
  return 0
}

# roadmap_unresolved ROOT REGISTER — every unresolved row below a milestone,
# one per line: "<register-rel>\t<id>\t<item>\t<state>\t<assigned>". First the
# milestone register's own rows, then the rows of every register covering a
# spec an epic row is assigned to. An epic marked done while its spec's
# register is still open is reported through the latter, which is how a
# premature "done" is caught.
roadmap_unresolved() {
  local root=$1 reg=$2 path rel id item assigned acceptance state note a f seen=""
  path=$root/$reg
  [ -f "$path" ] || return 0
  while IFS=$'\t' read -r id item assigned acceptance state note; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$reg" "$id" "$item" "$state" "${assigned:--}"
  done < <(register_open "$path")
  while IFS=$'\t' read -r id item assigned acceptance state note; do
    [ "$state" = "n/a" ] || [ "$state" = "deferred" ] && continue
    a=${assigned#\`}
    a=${a%\`}
    case $a in ''|-) continue ;; esac
    [ -f "$root/$a" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel=${f#"$root"/}
      [ "$rel" != "$reg" ] || continue
      case " $seen " in *" $rel "*) continue ;; esac
      seen="$seen $rel"
      while IFS=$'\t' read -r rid ritem rassigned racc rstate rnote; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$rid" "$ritem" "$rstate" "${rassigned:--}"
      done < <(register_open "$f")
    done < <(register_for_spec "$root" "$a")
  done < <(register_rows "$path")
  return 0
}

# roadmap_epic_counts ROOT REGISTER — "<resolved> <total>" over the epic rows.
roadmap_epic_counts() {
  local path="$1/$2"
  [ -f "$path" ] || { echo "0 0"; return 0; }
  register_rows "$path" | awk -F'\t' -v u=" $REGISTER_UNRESOLVED " '
    { t++; if (index(u, " " $5 " ") == 0) r++ }
    END { print r + 0, t + 0 }'
  return 0
}

# roadmap_line ROOT — the one-line summary the SessionStart hook injects.
roadmap_line() {
  local root=$1 file cur m name reg counts resolved total open_list
  file=$(roadmap_file "$root")
  [ -n "$file" ] || return 0
  cur=$(roadmap_current "$file")
  if [ -z "$cur" ]; then
    printf 'Roadmap: every milestone is closed (docs/superpowers/roadmap.md).\n'
    return 0
  fi
  IFS=$'\t' read -r m name _ reg _ _ <<<"$cur"
  read -r resolved total < <(roadmap_epic_counts "$root" "$reg")
  open_list=$(register_open "$root/$reg" 2>/dev/null | awk -F'\t' '
    NR <= 4 { printf "%s#%s %s", (NR > 1 ? ", " : ""), $1, $2 }
    END { if (NR > 4) printf " +%d more", NR - 4 }')
  if [ -n "$open_list" ]; then
    printf 'Roadmap: %s %s, %s of %s epics resolved, open: %s. A milestone closes only through dr-superpowers:closing-a-milestone.\n' \
      "$m" "$name" "$resolved" "$total" "$open_list"
  elif [ -n "$(roadmap_unresolved "$root" "$reg")" ]; then
    printf 'Roadmap: %s %s, every epic row resolved but requirement rows below them are open — run `scripts/roadmap open`.\n' "$m" "$name"
  else
    printf 'Roadmap: %s %s is ready to close with dr-superpowers:closing-a-milestone.\n' "$m" "$name"
  fi
  return 0
}
