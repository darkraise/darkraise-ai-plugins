# The register router next-step uses to pick the one next action from the open
# rows of the registers it reads. Sourced; defines functions only. It calls
# helpers the sourcing script defines (plan_name, plan_finished,
# execution_launch, launch_for) and the plan.sh, roots.sh and register.sh
# libraries.

# _plan_roots ROOT — "<root>\t<name prefix>" for each place a plan name can be
# read from: the docs root in use, then the docs directory and top level of the
# checkout and of every worktree (the primary among them).
_plan_roots() {
  local top=${_DFORGE_TOP:-$1} tree
  printf '%s\t%s\n' "$_DFORGE_DOCS_ROOT" "$(dforge_dir_rel docs "$top")"
  { printf '%s\n' "$top"; git -C "$top" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p'; } |
  while IFS= read -r tree; do
    tree=$(_dforge_path "$tree")
    printf '%s\t%s\n' "$(dforge_dir docs "$tree")" "$(dforge_dir_rel docs "$tree")"
    printf '%s\t\n' "$tree"
  done
}

# _spec_plan_files ROOT SPEC — "<name>\t<path>\t<sub-project or empty>" for
# every plan whose header Spec or Program line names SPEC, once per name key,
# the first place _plan_roots lists winning.
_spec_plan_files() {
  local want dir prefix f idx spec prog sub key seen="" files=() names=()
  want=$(dforge_name_key "$2")
  while IFS=$'\t' read -r dir prefix; do
    # A checkout's top level holds no plan directory of its own.
    [ -n "$prefix" ] && [ -d "$dir/plans" ] || continue
    for f in "$dir"/plans/*.md; do
      [ -s "$f" ] && [ "${f##*/}" != completed.md ] || continue
      files+=("$f") names+=("$prefix/plans/${f##*/}")
    done
  done < <(_plan_roots "$1")
  [ ${#files[@]} -gt 0 ] || return 0
  # \037, not a tab: a tab is IFS whitespace, so an empty field would vanish.
  while IFS=$'\037' read -r idx spec prog sub; do
    [ "$(dforge_name_key "$spec")" = "$want" ] || [ "$(dforge_name_key "$prog")" = "$want" ] || continue
    key=$(dforge_name_key "${names[idx - 1]}")
    case $seen in *"|$key|"*) continue ;; esac
    seen="$seen|$key|"
    printf '%s\t%s\t%s\n' "${names[idx - 1]}" "${files[idx - 1]}" "$sub"
  done < <(awk "$_PLAN_AWK"'
    function val(line, key,   v) {
      v = substr(line, length(key) + 1); sub(/^[ \t]+/, "", v)
      if (substr(v, 1, 1) == "`") { v = substr(v, 2); sub(/`.*$/, "", v) } else sub(/[ \t].*$/, "", v)
      return v
    }
    function emit() { if (task) print idx "\037" spec "\037" prog "\037" subp }
    FNR == 1 { if (idx) emit(); idx++; FENCE = ""; spec = ""; prog = ""; subp = ""; task = 0 }
    { sub(/\r$/, "") }
    in_fence($0) { next }
    is_task($0) >= 0 { task = 1; next }
    task { next }
    index($0, "**Spec:**") == 1 && spec == "" { spec = val($0, "**Spec:**") }
    index($0, "**Program:**") == 1 && prog == "" {
      prog = val($0, "**Program:**")
      if (match($0, /sub-project [0-9]+/)) { subp = substr($0, RSTART + 12, RLENGTH - 12) }
    }
    END { if (idx) emit() }
  ' "${files[@]}")
}

# spec_plans ROOT SPEC — the repository-relative name of every plan whose
# header Spec or Program line names SPEC, once per name key.
spec_plans() {
  _spec_plan_files "$1" "$2" | cut -f1
}

# _route_counted PLAN_PATH — true when a live plan's outcome can be read from
# completed.md: the index exists beside it and the plan is not older than the
# index's first entry, so it cannot be a plan finished before the index began.
_route_counted() {
  local index pdate cdate
  index="$(dirname "$1")/completed.md"
  [ -f "$index" ] || return 1
  pdate=$(basename "$1" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
  [ -n "$pdate" ] || return 1
  cdate=$(tr -d '\r' < "$index" | sed -nE 's/^- ([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/p' | head -n 1)
  [ -z "$cdate" ] || [[ ! $pdate < $cdate ]]
}

# _route_covers REGISTER SPEC — true when REGISTER's Covers line names SPEC.
_route_covers() {
  local cov want
  want=$(dforge_name_key "$2")
  while IFS= read -r cov; do
    [ "$(dforge_name_key "$cov")" != "$want" ] || return 0
  done < <(register_covers "$1")
  return 1
}

# _route_class ASSIGNED — the route of an Assigned cell, into _ROUTE_CLASS as
# "<kind>\036<rank>\036<target>\036<target path>\036<via spec>": kind rule,
# stale, plan, spec, unrecorded, finished (a spec whose plans are all
# finished), elsewhere or label.
_route_class() {
  local a=$1 plans name path sub live="" counted="" pick
  _ROUTE_CLASS=""
  if [ -z "$a" ] || [ "$a" = "-" ]; then
    _ROUTE_CLASS="rule"$'\036'4$'\036'"$a"$'\036\036'0
  elif [ "$(dforge_name_key "$(plan_name "$ROUTE_ROOT" "$a")")" = "$(dforge_name_key "$ROUTE_FINISHED")" ] || plan_finished "$ROUTE_ROOT" "$a"; then
    _ROUTE_CLASS="stale"
  elif [ -f "$(dforge_resolve "$a")" ]; then
    if [ -n "$(plan_tasks "$(dforge_resolve "$a")")" ] || [ -n "$(plan_lettered "$(dforge_resolve "$a")")" ]; then
      _ROUTE_CLASS="plan"$'\036'1$'\036'"$a"$'\036\036'0
      return 0
    fi
    # A spec's rows route by its plans: a live one is executed, none means
    # the spec still needs one, and once all are finished the row is a
    # requirement left over or an epic built and awaiting its audit.
    plans=$(_spec_plan_files "$ROUTE_ROOT" "$a")
    if [ -z "$plans" ]; then
      _ROUTE_CLASS="spec"$'\036'2$'\036'"$a"$'\036\036'0
      return 0
    fi
    while IFS=$'\t' read -r name path sub; do
      if [ "$(dforge_name_key "$name")" = "$(dforge_name_key "$ROUTE_FINISHED")" ] || plan_finished "$ROUTE_ROOT" "$name"; then
        continue
      fi
      if _route_counted "$path"; then
        counted="$counted$(printf '%06d\t%s\t%s\t%s' "${sub:-999999}" "$(basename "$path")" "$name" "$path")
"
      else
        live=1
      fi
    done <<<"$plans"
    if [ -n "$counted" ]; then
      # The lowest sub-project first, else the oldest filename date.
      pick=$(grep . <<<"$counted" | LC_ALL=C sort | awk 'NR == 1')
      _ROUTE_CLASS="plan"$'\036'1$'\036'"$(cut -f3 <<<"$pick")"$'\036'"$(cut -f4 <<<"$pick")"$'\036'1
    elif [ -n "$live" ]; then
      _ROUTE_CLASS="unrecorded"
    else
      _ROUTE_CLASS="finished"$'\036'2$'\036'"$a"$'\036\036'0
    fi
  elif [[ $a == *.md ]]; then
    _ROUTE_CLASS="elsewhere"
  else
    _ROUTE_CLASS="label"$'\036'3$'\036'"$a"$'\036\036'0
  fi
  return 0
}

# route_rows — classify the open rows on stdin, one per line:
# "<register>\t<id>\t<item>\t<assigned>\t<acceptance>\t<state>\t<note>".
# Reads ROUTE_ROOT, ROUTE_FINISHED, ROUTE_MS and ROUTE_OUTSIDE_MS; sets
# ROUTE_KIND, ROUTE_TARGET, ROUTE_ACTION, ROUTE_LAUNCH_CMD, ROUTE_LAUNCH_PLAN
# and the "#<id>" lists ROUTE_WAITING, ROUTE_BUILT, ROUTE_STALE,
# ROUTE_ELSEWHERE and ROUTE_UNRECORDED. Call it in the caller's own shell, never
# inside $(…), or the outputs are lost.
route_rows() {
  local rreg rid rassigned rstate a c r k t tpath vs best=9 target_path="" via_spec=0 \
    target_exec ms_id ms_name followups="" ids classes=$'\n' covered=$'\n'
  ROUTE_KIND="" ROUTE_TARGET="" ROUTE_ACTION="" ROUTE_LAUNCH_CMD="" ROUTE_LAUNCH_PLAN=""
  ROUTE_WAITING="" ROUTE_BUILT="" ROUTE_STALE="" ROUTE_ELSEWHERE="" ROUTE_UNRECORDED=""
  # The Assigned cell decides the route, not the row order. A row still on
  # a finished plan is the finishing session's to resolve and must never
  # route back to that plan; a verify row waits on a human check; a .md
  # path absent here belongs to another repository. Among the rest the
  # first row of the most concrete kind wins: a plan to execute, a spec to
  # plan, a label to specify, then a ruling on unassigned rows.
  while IFS=$'\037' read -r rreg rid _ rassigned _ rstate _; do
    a=${rassigned#\`}
    a=${a%\`}
    if [ "$rstate" = verify ]; then
      ROUTE_WAITING="${ROUTE_WAITING:+$ROUTE_WAITING, }#$rid"; continue
    fi
    # Rows sharing an Assigned cell route alike, so each cell is classified
    # once: a spec's classification reads every plan file.
    case $classes in
      *$'\n'"$a"$'\035'*) c=${classes#*$'\n'"$a"$'\035'}; c=${c%%$'\n'*} ;;
      *) _route_class "$a"; c=$_ROUTE_CLASS; classes="$classes$a"$'\035'"$c"$'\n' ;;
    esac
    IFS=$'\036' read -r k r t tpath vs <<<"$c"
    case $k in
      stale) ROUTE_STALE="${ROUTE_STALE:+$ROUTE_STALE, }#$rid"; continue ;;
      elsewhere) ROUTE_ELSEWHERE="${ROUTE_ELSEWHERE:+$ROUTE_ELSEWHERE, }#$rid"; continue ;;
      unrecorded) ROUTE_UNRECORDED="${ROUTE_UNRECORDED:+$ROUTE_UNRECORDED, }#$rid"; continue ;;
      finished)
        case $covered in
          *$'\n'"$rreg"$'\035'"$a"$'\035'*) c=${covered#*$'\n'"$rreg"$'\035'"$a"$'\035'}; c=${c%%$'\n'*} ;;
          *) if _route_covers "$rreg" "$a"; then c=1; else c=0; fi; covered="$covered$rreg"$'\035'"$a"$'\035'"$c"$'\n' ;;
        esac
        if [ "$c" -eq 1 ]; then
          followups="$followups$(dforge_name_key "$a")	#$rid
"
          r=2 k=followup
        else
          ROUTE_BUILT="${ROUTE_BUILT:+$ROUTE_BUILT, }#$rid"; continue
        fi
        ;;
    esac
    if [ "$r" -lt "$best" ]; then best=$r ROUTE_TARGET=$t ROUTE_KIND=$k target_path=$tpath via_spec=$vs; fi
  done < <(tr '\t' '\037')

  ROUTE_LAUNCH_CMD=$(launch_for design)
  case $ROUTE_KIND in
    plan)
      [ -n "$target_path" ] || target_path=$(dforge_resolve "$ROUTE_TARGET")
      target_exec=$(plan_header_line "$target_path" Execution)
      if plan_ledger_any "$ROUTE_ROOT" "$target_path" >/dev/null; then
        ROUTE_ACTION="Resume \`$ROUTE_TARGET\` with dforge:resume-execution."
      else
        ROUTE_ACTION="Continue \`$ROUTE_TARGET\` with dforge:executing-plans."
      fi
      [ "$via_spec" -eq 0 ] || ROUTE_ACTION="$ROUTE_ACTION If it was abandoned, record it in completed.md or delete it."
      ROUTE_LAUNCH_CMD=$(execution_launch "$target_exec") ROUTE_LAUNCH_PLAN=$ROUTE_TARGET
      ;;
    spec)  ROUTE_ACTION="\`$ROUTE_TARGET\`: write its plan with dforge:writing-plans." ;;
    followup)
      ids=$(ROUTE_KEY=$(dforge_name_key "$ROUTE_TARGET") awk -F'\t' '$1 == ENVIRON["ROUTE_KEY"] { printf "%s%s", (n++ ? ", " : ""), $2 }' <<<"$followups")
      ROUTE_ACTION="\`$ROUTE_TARGET\`: write a follow-up plan for rows $ids with dforge:writing-plans."
      ;;
    label) ROUTE_ACTION="\`$ROUTE_TARGET\`: write its spec in a fresh session." ;;
    rule)  ROUTE_ACTION="Rule on the open rows with dforge:brainstorming." ;;
    *)
      [ -z "$ROUTE_WAITING" ] || ROUTE_ACTION="Awaiting your check (verify): $ROUTE_WAITING."
      [ -z "$ROUTE_ELSEWHERE" ] || ROUTE_ACTION="${ROUTE_ACTION:+$ROUTE_ACTION }Assigned outside this repository: $ROUTE_ELSEWHERE."
      [ -z "$ROUTE_UNRECORDED" ] || ROUTE_ACTION="${ROUTE_ACTION:+$ROUTE_ACTION }Spec plans exist, outcome unrecorded: $ROUTE_UNRECORDED."
      # The milestone audit is the check a verify row waits on, and a built
      # epic's, so a milestone with nothing else unresolved goes to it.
      if [ -n "$ROUTE_MS" ] && [ -n "$ROUTE_WAITING$ROUTE_BUILT" ] && [ -z "$ROUTE_STALE$ROUTE_ELSEWHERE$ROUTE_UNRECORDED$ROUTE_OUTSIDE_MS" ]; then
        ROUTE_KIND=milestone
        ms_id=$(cut -f1 <<<"$ROUTE_MS") ms_name=$(cut -f2 <<<"$ROUTE_MS")
        [ -z "$ROUTE_BUILT" ] || ROUTE_ACTION="${ROUTE_ACTION:+$ROUTE_ACTION }Built, awaiting the audit: $ROUTE_BUILT."
        ROUTE_ACTION="$ROUTE_ACTION Milestone $ms_id ($ms_name) has nothing else open: audit and close it with dforge:closing-a-milestone."
      fi
      ;;
  esac
  return 0
}
