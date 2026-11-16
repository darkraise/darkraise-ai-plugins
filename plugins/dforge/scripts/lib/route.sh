# The register router next-step uses to pick the one next action from the open
# rows of the registers it reads. Sourced; defines functions only. It calls
# helpers the sourcing script defines (plan_name, plan_finished,
# execution_launch, launch_for) and the plan.sh and roots.sh libraries.

# route_rows — classify the open rows on stdin, one per line:
# "<register>\t<id>\t<item>\t<assigned>\t<acceptance>\t<state>\t<note>".
# Reads ROUTE_ROOT, ROUTE_FINISHED, ROUTE_MS and ROUTE_OUTSIDE_MS; sets
# ROUTE_KIND, ROUTE_TARGET, ROUTE_ACTION, ROUTE_LAUNCH_CMD, ROUTE_LAUNCH_PLAN
# and the "#<id>" lists ROUTE_WAITING, ROUTE_BUILT, ROUTE_STALE,
# ROUTE_ELSEWHERE and ROUTE_UNRECORDED. Call it in the caller's own shell, never
# inside $(…), or the outputs are lost.
route_rows() {
  local rid rassigned rstate a r k best=9 target_exec ms_id ms_name
  ROUTE_KIND="" ROUTE_TARGET="" ROUTE_ACTION="" ROUTE_LAUNCH_CMD="" ROUTE_LAUNCH_PLAN=""
  ROUTE_WAITING="" ROUTE_BUILT="" ROUTE_STALE="" ROUTE_ELSEWHERE="" ROUTE_UNRECORDED=""
  # The Assigned cell decides the route, not the row order. A row still on
  # a finished plan is the finishing session's to resolve and must never
  # route back to that plan; a verify row waits on a human check; a .md
  # path absent here belongs to another repository. Among the rest the
  # first row of the most concrete kind wins: a plan to execute, a spec to
  # plan, a label to specify, then a ruling on unassigned rows.
  while IFS=$'\037' read -r _ rid _ rassigned _ rstate _; do
    a=${rassigned#\`}
    a=${a%\`}
    if [ "$rstate" = verify ]; then
      ROUTE_WAITING="${ROUTE_WAITING:+$ROUTE_WAITING, }#$rid"; continue
    elif [ -z "$a" ] || [ "$a" = "-" ]; then
      r=4 k=rule
    elif [ "$(dforge_name_key "$(plan_name "$ROUTE_ROOT" "$a")")" = "$(dforge_name_key "$ROUTE_FINISHED")" ] || plan_finished "$ROUTE_ROOT" "$a"; then
      ROUTE_STALE="${ROUTE_STALE:+$ROUTE_STALE, }#$rid"; continue
    elif [ -f "$(dforge_resolve "$a")" ]; then
      if [ -n "$(plan_tasks "$(dforge_resolve "$a")")" ] || [ -n "$(plan_lettered "$(dforge_resolve "$a")")" ]; then r=1 k=plan; else r=2 k=spec; fi
    elif [[ $a == *.md ]]; then
      ROUTE_ELSEWHERE="${ROUTE_ELSEWHERE:+$ROUTE_ELSEWHERE, }#$rid"; continue
    else
      r=3 k=label
    fi
    if [ "$r" -lt "$best" ]; then best=$r ROUTE_TARGET=$a ROUTE_KIND=$k; fi
  done < <(tr '\t' '\037')

  ROUTE_LAUNCH_CMD=$(launch_for design)
  case $ROUTE_KIND in
    plan)
      target_exec=$(plan_header_line "$(dforge_resolve "$ROUTE_TARGET")" Execution)
      if [ -n "$(plan_ledger "$(dforge_resolve "$ROUTE_TARGET")")" ]; then
        ROUTE_ACTION="Resume \`$ROUTE_TARGET\` with dforge:resume-execution."
      else
        ROUTE_ACTION="Continue \`$ROUTE_TARGET\` with dforge:executing-plans."
      fi
      ROUTE_LAUNCH_CMD=$(execution_launch "$target_exec") ROUTE_LAUNCH_PLAN=$ROUTE_TARGET
      ;;
    spec)  ROUTE_ACTION="\`$ROUTE_TARGET\`: write its plan with dforge:writing-plans." ;;
    label) ROUTE_ACTION="\`$ROUTE_TARGET\`: write its spec in a fresh session." ;;
    rule)  ROUTE_ACTION="Rule on the open rows with dforge:brainstorming." ;;
    *)
      [ -z "$ROUTE_WAITING" ] || ROUTE_ACTION="Awaiting your check (verify): $ROUTE_WAITING."
      [ -z "$ROUTE_ELSEWHERE" ] || ROUTE_ACTION="${ROUTE_ACTION:+$ROUTE_ACTION }Assigned outside this repository: $ROUTE_ELSEWHERE."
      # The milestone audit is the check a verify row waits on, so a
      # milestone with nothing else unresolved goes to it.
      if [ -n "$ROUTE_MS" ] && [ -n "$ROUTE_WAITING" ] && [ -z "$ROUTE_STALE$ROUTE_ELSEWHERE$ROUTE_OUTSIDE_MS" ]; then
        ROUTE_KIND=milestone
        ms_id=$(cut -f1 <<<"$ROUTE_MS") ms_name=$(cut -f2 <<<"$ROUTE_MS")
        ROUTE_ACTION="$ROUTE_ACTION Milestone $ms_id ($ms_name) has nothing else open: audit and close it with dforge:closing-a-milestone."
      fi
      ;;
  esac
  return 0
}
