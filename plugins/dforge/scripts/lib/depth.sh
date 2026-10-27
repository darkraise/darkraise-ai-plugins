# Review depth: the one rule that sizes the spec, plan and final-review stages
# of an architectural plan as light, standard or full. Sourced after
# lib/plan.sh by depth-route, review-route and lens-route, so the three agree
# and none shells out to another. Defines functions only.

[ -n "${DEPTH_TRIGGERS+x}" ] || readonly -a DEPTH_TRIGGERS=(new-subsystem interface unenumerable approach risk intricate asked)

# depth_rank DEPTH — 0, 1 or 2 for light, standard, full; status 1 otherwise.
depth_rank() {
  case ${1:-} in
    light) echo 0 ;;
    standard) echo 1 ;;
    full) echo 2 ;;
    *) return 1 ;;
  esac
}

# depth_name RANK — the depth a rank names; status 1 for any other value.
depth_name() {
  case ${1:-} in
    0) echo light ;;
    1) echo standard ;;
    2) echo full ;;
    *) return 1 ;;
  esac
}

# depth_from_triggers LIST — "<depth><TAB><reason>" for a comma-separated list
# of trigger ids. Status 2 and a stderr message, with no stdout, for an empty
# list or an id outside DEPTH_TRIGGERS.
depth_from_triggers() {
  local ids=() id known t risk=0 sub=0 iface=0 reason
  IFS=, read -ra ids <<<"${1:-}"
  local given=()
  for id in ${ids[@]+"${ids[@]}"}; do
    [ -z "$id" ] || given+=("$id")
  done
  if [ "${#given[@]}" -eq 0 ]; then
    echo "no trigger given" >&2
    return 2
  fi
  for id in "${given[@]}"; do
    known=0
    for t in "${DEPTH_TRIGGERS[@]}"; do
      [ "$t" != "$id" ] || known=1
    done
    if [ "$known" -eq 0 ]; then
      echo "unknown trigger: $id" >&2
      return 2
    fi
    case $id in
      risk) risk=1 ;;
      new-subsystem) sub=1 ;;
      interface) iface=1 ;;
    esac
  done
  if [ "$risk" -eq 1 ] || [ "$sub" -eq 1 ]; then
    reason=""
    [ "$risk" -eq 0 ] || reason=risk
    [ "$sub" -eq 0 ] || reason="${reason:+$reason,}new-subsystem"
    printf 'full\t%s\n' "$reason"
  elif [ "$iface" -eq 1 ]; then
    printf 'standard\tinterface\n'
  else
    reason=$(IFS=,; printf '%s' "${given[*]}")
    printf 'light\t%s\n' "$reason"
  fi
}

# depth_spec_file SPEC_FILE — the first word after **Depth:** on the first line
# outside a fenced block that begins with it, above the spec's first "## "
# heading, when that word is a depth; "none" for a missing file, no such line,
# or any other word. A body that quotes a Depth line must not stand in for a
# header that lacks one, which would lower an old spec below full. awk reads to
# the end rather than exiting early: an early exit can leave tr on a closed
# pipe, which pipefail reports.
depth_spec_file() {
  local word=""
  if [ -f "${1:-}" ]; then
    word=$(tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
      in_fence($0) { next }
      /^## / { done = 1 }
      !done && /^\*\*Depth:\*\*/ { sub(/^\*\*Depth:\*\*[ \t]*/, ""); print $1; done = 1 }')
  fi
  case $word in
    light|standard|full) printf '%s\n' "$word" ;;
    *) echo none ;;
  esac
}

# depth_plan SRC ROOT — the plan checkpoint for SRC, a plan file with its
# amendments applied, whose **Spec:** path resolves against the checkout ROOT:
#   depth=<d> spec=<d|none> tasks=<d> reason=<items>
# The plan never lowers the spec's depth; a missing spec depth or a Host: codex
# header raises it to full.
depth_plan() {
  local src=$1 root=$2 header spec_line spec_path spec_file spec tasks depth
  local codex=0 n t r hi=-1 hi_task="" unscored="" reasons=()
  header=$(plan_header "$src")
  grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$header" && codex=1

  spec_line=$(awk "$_PLAN_AWK"'
    in_fence($0) { next }
    !done && index($0, "**Spec:**") == 1 { print; done = 1 }' <<<"$header")
  spec=none
  if [ -n "$spec_line" ]; then
    spec_path=$(sed -E 's/^\*\*Spec:\*\*[ \t]*(`([^`]+)`|([^ \t]+)).*/\2\3/' <<<"$spec_line")
    if [ -n "$spec_path" ] && [ "$spec_path" != "$spec_line" ]; then
      dforge_stores_init "$root"
      spec_file=$(dforge_resolve "$spec_path" "$root")
      spec=$(depth_spec_file "$spec_file")
    fi
  fi

  while IFS=$'\t' read -r n t r; do
    [ -n "$n" ] || continue
    if [ "$r" = "-" ] || [ "$r" = "?" ]; then
      [ -n "$unscored" ] || unscored=$n
    elif [ "$r" -gt "$hi" ]; then
      hi=$r hi_task=$n
    fi
  done < <(plan_scores "$src")
  if [ -n "$unscored" ] || [ "$hi" -ge 3 ]; then tasks=full
  elif [ "$hi" -eq 2 ]; then tasks=standard
  else tasks=light
  fi

  if [ "$codex" -eq 1 ] || [ "$spec" = none ]; then depth=full
  elif [ "$(depth_rank "$spec")" -ge "$(depth_rank "$tasks")" ]; then depth=$spec
  else depth=$tasks
  fi

  if [ "$codex" -eq 1 ]; then
    reasons=(codex-host)
  else
    [ "$spec" != none ] || reasons+=(no-spec-depth)
    [ "$spec" != "$depth" ] || reasons+=(spec)
    if [ -n "$unscored" ]; then
      reasons+=("unscored:$unscored")
    elif [ "$tasks" = "$depth" ] && [ -n "$hi_task" ]; then
      reasons+=("task-risk:$hi_task")
    fi
  fi
  printf 'depth=%s spec=%s tasks=%s reason=%s\n' "$depth" "$spec" "$tasks" "$(IFS=,; printf '%s' "${reasons[*]}")"
}

# depth_plan_depth SRC ROOT — only the depth of depth_plan.
depth_plan_depth() {
  local line
  line=$(depth_plan "$1" "$2") || return $?
  line=${line#depth=}
  printf '%s\n' "${line%% *}"
}
