#!/usr/bin/env bash
# Runs one plan task on Codex and leaves behind a superpowers-shaped report.
#
# The Codex CLI validates neither --model nor model_reasoning_effort: it accepts
# any string, prints it in its banner, and fails at the API. Validating here is
# what keeps a typo from becoming a paid round trip.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
SCHEMA="$HERE/codex-report-schema.json"
source "$HERE/lib/task-state.sh"
source "$HERE/lib/task-execution.sh"

VALID_EFFORTS="low medium high xhigh ultra"

die() { printf 'run-codex-task: %s\n' "$1" >&2; exit 2; }

block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

brief="" report="" model="" effort="" cwd="" timeout_s="" thread="" dry=0
task_id='' write_set='' operation='' operation_value='' approval='' review_round=''
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift; continue ;;
    --recover-commit|--handback|--release)
      [ -z "$operation" ] || die 'control operations are mutually exclusive'
      operation="${1#--}"; shift; continue ;;
    --brief|--report|--model|--effort|--cwd|--timeout|--resume|--task-id|--write-set|--amend-write-set|--accept-baseline|--approval|--review-round) ;;
    *) die "unknown argument: $1" ;;
  esac
  # Every flag reaching here takes a value. `shift 2` fails when only one
  # positional remains, and with no `set -e` the loop would re-enter with $1
  # unchanged and spin forever instead of reporting the malformed input.
  [ $# -ge 2 ] || die "missing value for $1"
  case "$1" in
    --brief)   brief="$2" ;;
    --report)  report="$2" ;;
    --model)   model="$2" ;;
    --effort)  effort="$2" ;;
    --cwd)     cwd="$2" ;;
    --timeout) timeout_s="$2" ;;
    --resume)  thread="$2" ;;
    --task-id) task_id="$2" ;;
    --write-set) write_set="$2" ;;
    --approval) approval="$2" ;;
    --review-round) review_round="$2" ;;
    --amend-write-set|--accept-baseline)
      [ -z "$operation" ] || die 'control operations are mutually exclusive'
      operation="${1#--}"; operation_value="$2" ;;
  esac
  shift 2
done

if [ -n "$operation" ]; then
  [ "$dry" -eq 0 ] && [ -n "$cwd" ] && [ -n "$task_id" ] || die 'control operations require --cwd and --task-id'
  dr_task_open "$cwd" "$task_id" || die 'cannot open task for recovery'
  trap 'dr_task_unlock' EXIT
  dr_task_control "$operation" "$operation_value" "$approval" || die "control operation failed: $operation"
  exit 0
fi

[ -n "$brief" ]  || die "--brief is required"
[ -n "$report" ] || die "--report is required"
[ -n "$model" ]  || die "--model is required"
[ -n "$effort" ] || die "--effort is required"
[ -n "$cwd" ]    || die "--cwd is required"
[ -f "$brief" ]  || die "brief not found: $brief"
[ -d "$cwd" ]    || die "cwd not found: $cwd"
[ -f "$SCHEMA" ] || die "schema not found: $SCHEMA"
# Every verdict this wrapper reports is parsed with jq. Without it the parse
# below would fall back to BLOCKED, which is indistinguishable from a real
# block: the controller would spend a rung and a second paid run to learn
# nothing. The durable phase distinguishes preflight failures from failures after execution.
command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"

# Resolved once: reset pathspecs are repo-relative while these files are written
# caller-relative, and `git reset` on a non-matching path exits 0, so the miss
# would be silent.
case "$report" in /*|[A-Za-z]:*) ;; *) report="$(pwd)/$report" ;; esac
# Checked here rather than discovered at the first redirect: a bad report
# directory would otherwise print shell redirect errors, never run Codex, and
# exit 1 - the code the skill defines as "Codex ran and did not reach DONE",
# costing the controller a rung for a typo.
[ -d "$(dirname "$report")" ] || die "report directory not found: $(dirname "$report")"

block codex-assignment | awk '{print $2}' | sort -u | grep -qxF -- "$model" \
  || die "model is not a rung in codex-assignment: $model"
# Word-exact, mirroring the model check above. A containment test on the padded
# string admits a multi-word value like "medium high", which would then fail far
# downstream in the timeout lookup instead of here.
printf '%s\n' $VALID_EFFORTS | grep -qxF -- "$effort" \
  || die "invalid reasoning effort: $effort (valid: $VALID_EFFORTS)"

if [ -z "$timeout_s" ]; then
  timeout_s=$(block codex-timeout | awk -v k="$model/$effort" '$1 == k {print $2}')
  [ -n "$timeout_s" ] || die "no codex-timeout row for $model/$effort"
fi
# Whole seconds only. `[ "$waited" -lt "$timeout_s" ]` errors and evaluates
# false on a value like "30m", so the poll loop never runs, the tree is killed
# about a second after launch, and the run is reported as BLOCKED - the exact
# opposite of what raising the timeout was meant to do.
printf '%s' "$timeout_s" | grep -qE '^[0-9]+$' || die "--timeout must be whole seconds: $timeout_s"
if [ -n "$review_round" ]; then
  [[ "$review_round" =~ ^[1-5]$ ]] && [ -n "$thread" ] || die '--review-round requires a resume and a round from 1 to 5'
fi

# Every per-invocation flag is rebuilt here, including on resume: a bare
# `codex exec resume <id>` inherits the user's config defaults instead.
#
# -C and -s must precede the subcommand. `codex exec resume` accepts neither -
# 0.153.4 answers `error: unexpected argument '-C' found` and exits before any
# model call - while `codex exec` takes both and honours them for the resumed
# thread. Every other flag below is accepted in either position, so it stays
# after, which keeps the two forms one argv apart.
argv=(exec -C "$cwd" -s workspace-write)
[ -n "$thread" ] && argv+=(resume "$thread")
argv+=(
  -m "$model"
  -c "model_reasoning_effort=$effort"
  --json
  --output-schema "$SCHEMA"
  -o "$report.last.json"
)

if [ "$dry" -eq 1 ]; then
  # Two separate lines, not one: execution no longer wraps codex in `timeout`
  # (that would reinsert a process between the wrapper and node, breaking
  # taskkill's native tree-walk - see kill_codex_tree below), so a dry run
  # that printed "timeout $s codex ..." would show a command that never
  # actually runs. %q, not %s, on the invocation: a path containing a space
  # silently splits into several arguments under %s.
  printf 'timeout=%s\n' "$timeout_s"
  printf 'codex'
  printf ' %q' "${argv[@]}"
  printf '\n'
  exit 0
fi

command -v timeout >/dev/null 2>&1 || die 'GNU timeout is required but not on PATH'
[ -n "$task_id" ] || die '--task-id is required'
cwd="$(dr_canonical "$cwd")" || die 'cannot resolve worktree'
report="$(realpath -m -- "$report")" || die 'cannot resolve report path'
case "$report" in
  "$cwd"/*)
    case "$report" in "$cwd"/.superpowers/*) ;; *) die 'report must be outside checkout or in ignored .superpowers workspace' ;; esac
    git -C "$cwd" check-ignore -q -- "$report" || die 'report workspace is not ignored'
    [ -z "$(git -C "$cwd" ls-files -- "$report")" ] || die 'report cannot be tracked' ;;
esac
dr_task_open "$cwd" "$task_id" "$write_set" || die 'task preflight failed'
trap 'dr_task_unlock' EXIT
record="$DR_TASK_DIR/state.json"
phase="$(jq -r .phase "$record")"
case "$phase" in ready|pending|complete) ;; *) die "task phase $phase requires explicit recovery" ;; esac
[ "$(jq -r '.released // false' "$record")" = false ] || die 'task ownership was released; use a new task ID'
[ "$(git -C "$cwd" rev-parse HEAD)" = "$(jq -r .expected_head "$record")" ] || die 'HEAD drift requires reconciliation'
before_snapshot="$DR_TASK_DIR/before.json"
if [ "$phase" != ready ]; then
  jq '.pending // .baseline' "$record" > "$before_snapshot" && dr_task_assert_snapshot "$before_snapshot" || die 'pending/index/worktree drift requires reconciliation'
fi
if [ -n "$thread" ]; then
  jq -e --arg thread "$thread" --arg model "$model" --arg effort "$effort" \
    '.thread == $thread and .model == $model and .effort == $effort' "$record" >/dev/null || die 'resume thread/model/effort does not match task record'
fi
if [ -n "$review_round" ]; then
  [ "$review_round" -ge "$(jq -r .review_rounds "$record")" ] || die 'review round cannot move backwards'
fi
dr_snapshot "$cwd" "$before_snapshot" || die 'cannot snapshot worktree'
human_report="$report"
attempt="$(jq '.attempts | length + 1' "$record")"
report="$DR_TASK_DIR/attempt-$attempt.md"
argv[${#argv[@]}-1]="$report.last.json"
dr_task_update '.model = $model | .effort = $effort | .baseline = $snapshot[0] | .candidate = null |
  .attempts += [{number:$attempt,model:$model,effort:$effort,resume:$resume,prior_thread:.thread}] |
  .review_rounds = (if $review_round == "" then .review_rounds else ($review_round | tonumber) end) |
  .artifacts = {report:$report,prompt:($report + ".prompt.md"),jsonl:($report + ".jsonl"),last:($report + ".last.json"),stderr:($report + ".stderr")}' \
  --arg model "$model" --arg effort "$effort" --arg resume "$thread" --argjson attempt "$attempt" \
  --arg review_round "$review_round" \
  --arg report "$report" --slurpfile snapshot "$before_snapshot" || die 'cannot persist attempt'

prompt="$report.prompt.md"
jsonl="$report.jsonl"
last="$report.last.json"

{
  cat "$brief"
  # Codex reads AGENTS.md, never CLAUDE.md, and the host repo may have neither.
  # Inlining beats assuming: this plugin ships to arbitrary repositories, and
  # writing an AGENTS.md would change the user's own Codex sessions too.
  for f in CLAUDE.md AGENTS.md; do
    if [ -f "$cwd/$f" ]; then
      printf '\n\n## Repository conventions (%s)\n\n' "$f"
      cat "$cwd/$f"
    fi
  done
  printf '\n\n'
  cat "$HERE/codex-task-contract.md"
} > "$prompt"

# --show-prefix avoids comparing native Windows paths with MSYS paths.
prefix=$(git -C "$cwd" rev-parse --show-prefix) || die "not a git repository: $cwd"
[ -z "$prefix" ] || die "cwd must be the repository root, but sits under $prefix"
base=$(git -C "$cwd" rev-parse HEAD) || die "cannot resolve HEAD in $cwd"

codex_pid=""
codex_winpid=""
# Two mechanisms for two topologies. kill -TERM -<pgid> reaches MSYS-aware
# descendants sharing the set -m group, and taskkill //T walks native
# ParentProcessId. Only the first is proven necessary: taskkill alone leaves an
# MSYS grandchild alive. The group kill was also observed to reach native
# grandchildren, by a mechanism nobody has explained - taskkill stays because
# that observation is unexplained, not because it is known to be redundant.
kill_codex_tree() {
  [ -n "$codex_pid" ] || return 0
  local current_start
  current_start=$(awk '{print $22}' "/proc/$codex_pid/stat" 2>/dev/null || true)
  if [ -n "$current_start" ] && [ -n "${codex_start:-}" ] && [ "$current_start" != "$codex_start" ]; then return 1; fi
  if [ -n "$codex_winpid" ] && [ -n "$current_start" ] && [ "$current_start" = "${codex_start:-}" ]; then
    taskkill //F //T //PID "$codex_winpid" >/dev/null 2>&1
  fi
  kill -TERM -"$codex_pid" 2>/dev/null || true
  sleep 1
  kill -0 -"$codex_pid" 2>/dev/null && kill -KILL -"$codex_pid" 2>/dev/null
  return 0
}
cleanup() {
  if [ -z "$codex_pid" ] && jq -e '.phase == "running" and any(.processes[]; .identity == "launch-pending")' "$record" >/dev/null 2>&1; then
    dr_task_block 'launch interrupted before process identity was recorded; manual writer reconciliation required' || true
    return 0
  fi
  [ -n "$codex_pid" ] && kill_codex_tree
  if [ -n "$codex_pid" ] && kill -0 -"$codex_pid" 2>/dev/null; then
    dr_task_block 'owned process group may still be running' || true
    return 0
  fi
  if [ "$(jq -r .phase "$record" 2>/dev/null)" = running ]; then
    dr_task_update '.processes = []' && dr_task_block 'execution interrupted; reconcile the recorded snapshot' || true
  fi
  dr_task_unlock
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Codex can exit 0 without writing its final message. Left in place, a previous
# run's verdict would be read as this one's - guaranteed on every resume round,
# which reuses the same report path - and the wrapper would commit under a stale
# subject it never earned. $report is cleared for the same reason: a die path
# below (a failed add or commit) leaves the previous round's report in place,
# complete and carrying `status: DONE`, while the exit-2 recovery text tells the
# controller no report was written. rm -f succeeds on a missing file but can
# fail on a locked one, so the clear is verified rather than assumed.
rm -f "$last" "$jsonl" "$report"
[ ! -f "$last" ] || die "could not clear stale verdict file: $last"

# A non-interactive script has job control off, so a plain `cmd &` inherits
# this script's own process group instead of getting a fresh one - confirmed
# live: `kill -TERM -"$codex_pid"` then fails with "No such process" because
# no group with that id exists. `set -m` around just this launch is what makes
# the backgrounded job (and anything it execs) its own group, which is what
# `kill_codex_tree` signals; `setsid` would do the same but isn't on this box.
set -m
dr_task_update '.phase = "running" | .processes = [{identity:"launch-pending"}]' || die 'cannot persist running phase'
codex "${argv[@]}" < "$prompt" > "$jsonl" 2> "$report.stderr" &
codex_pid=$!
set +m
# Captured once, right after launch, while codex_pid (node) is still alive:
# this is node's own Windows process, which is what taskkill //T needs to
# start its native tree-walk from.
codex_winpid=$(cat "/proc/$codex_pid/winpid" 2>/dev/null || true)
codex_start=$(awk '{print $22}' "/proc/$codex_pid/stat" 2>/dev/null || true)
dr_task_update '.processes = [{pid:$pid,winpid:$winpid,start:$start,group:$pid}]' \
  --arg pid "$codex_pid" --arg winpid "$codex_winpid" --arg start "$codex_start" || die 'cannot persist process identity'

# Polled rather than wrapped in `timeout`: the kill has to happen while the
# child is still live. `timeout` reaps its child before wait returns, leaving
# nothing left to signal by the time a kill would fire - and it would also put
# a wrapper process between us and node, which is exactly what breaks
# taskkill's native tree-walk (see codex_winpid above).
timed_out=no
waited=0
while [ "$waited" -lt "$timeout_s" ] && kill -0 "$codex_pid" 2>/dev/null; do
  discovered_thread="$(jq -r '.thread_id // .threadId // .session_id // .sessionId // empty' "$jsonl" 2>/dev/null | head -1)"
  if [ -n "$discovered_thread" ]; then dr_task_update '.thread = $thread' --arg thread "$discovered_thread" || die 'cannot persist thread'; fi
  sleep 1
  waited=$((waited + 1))
done
if kill -0 "$codex_pid" 2>/dev/null; then
  timed_out=yes
  kill_codex_tree
fi

# Bounded rather than a bare `wait`: a child that survived both signals would
# block forever, and this wrapper must always return a status line to the
# controller. Reintroducing `timeout` is not the answer - it would reinsert a
# process between us and node, which is what made taskkill unable to walk the
# native tree.
grace=0
while [ "$grace" -lt 30 ] && kill -0 "$codex_pid" 2>/dev/null; do
  sleep 1
  grace=$((grace + 1))
done
survivor=no
if kill -0 "$codex_pid" 2>/dev/null; then
  rc=124
  # Both kills plus the grace window have already been spent, so this process
  # outlived everything the wrapper can do about it. Saying so is what stops a
  # retry from putting a second Codex into the same worktree.
  survivor=yes
else
  wait "$codex_pid"; rc=$?
  if kill -0 -"$codex_pid" 2>/dev/null; then
    kill_codex_tree
    if kill -0 -"$codex_pid" 2>/dev/null; then
      dr_task_block 'child group survived parent exit'
      die 'child group remains; ownership stays reserved'
    fi
  fi
  codex_pid=""
  codex_winpid=""
fi
[ "$timed_out" = yes ] && rc=124
[ "$survivor" = no ] || { dr_task_block 'child survived termination'; die 'child still running'; }
dr_task_update '.processes = []' || die 'cannot persist child termination'

# Event field naming has varied across Codex releases, so match on any of the
# shapes rather than pinning one that a later version may rename.
thread_id=$(jq -r 'select(type=="object")
  | (.thread_id // .threadId // .session_id // .sessionId // empty)' \
  "$jsonl" 2>/dev/null | head -1)
[ -n "$thread_id" ] || thread_id="${thread:-unknown}"
dr_task_update '.thread = $thread' --arg thread "$thread_id" || die 'cannot persist task thread'

# Codex reports API failures - quota, rate limit, 5xx, auth - as events on the
# --json stream, which is stdout and lands in $jsonl. They never reach stderr,
# which holds only the CLI's own chatter. Extracting the message here is what
# lets the controller tell a transient failure from a capability one without
# opening a JSONL file by hand. The first error event carries the fuller text;
# the turn.failed that follows repeats it in short form.
codex_error=$(jq -r '
  select(type == "object")
  | select(.type == "error" or .type == "turn.failed")
  | [.message?, (.error? | objects | .message?)]
  | map(select(. != null and . != ""))
  | .[0] // empty
' "$jsonl" 2>/dev/null | head -1)

status=BLOCKED
summary=""
subject=""
if [ -f "$last" ]; then
  status=$(jq -r '.status // "BLOCKED"' "$last" 2>/dev/null || echo BLOCKED)
  summary=$(jq -r '.summary // ""' "$last" 2>/dev/null || true)
  subject=$(jq -r '.commit_subject // ""' "$last" 2>/dev/null || true)
fi
# The verdict is forced to BLOCKED on a non-zero exit, which is why $rc is
# reported separately below: collapsing the two makes an argument-parse failure
# at 50 ms and a model that gave up after 20 minutes read identically.
[ "$rc" -eq 0 ] || status=BLOCKED

committed=no
if [ "$status" = DONE ]; then
  dr_task_stage "$before_snapshot" "$subject" || die 'staging/commit failed; inspect durable task record and recover explicitly'
  if [ "$(git -C "$cwd" rev-parse HEAD)" = "$base" ]; then committed=empty; else committed=yes; fi
else
  dr_task_validate_scope "$before_snapshot" || { dr_task_block 'unexpected diff after incomplete run'; die 'task scope drift'; }
  dr_snapshot "$cwd" "$DR_TASK_DIR/pending-snapshot.json" &&
    dr_task_update '.phase = "pending" | .pending = $snapshot[0]' --slurpfile snapshot "$DR_TASK_DIR/pending-snapshot.json" || die 'cannot persist pending task'
fi

head=$(git -C "$cwd" rev-parse HEAD)

{
  printf '# Task report\n\n'
  printf -- '- executor: codex %s / %s\n' "$model" "$effort"
  printf -- '- thread: %s\n' "$thread_id"
  printf -- '- status: %s\n' "$status"
  printf -- '- exit: %s\n' "$rc"
  printf -- '- commits: %s..%s\n' "${base:0:7}" "${head:0:7}"
  [ "$committed" = empty ] && printf -- '- note: DONE with an empty diff; nothing was committed\n'
  [ "$timed_out" = yes ] && printf -- '- note: timed out after %ss and codex was killed; raise --timeout rather than taking the successor rung\n' "$timeout_s"
  [ "$survivor" = yes ] && printf -- '- note: a codex process may still be running (pid %s); check before retrying in this worktree\n' "$codex_pid"
  printf '\n## Summary\n\n%s\n' "$summary"
  if [ "$status" = NEEDS_CONTEXT ]; then
    printf '\n## Questions\n\n'
    jq -r '.questions[]? | "- " + .' "$last" 2>/dev/null || true
  fi
  if [ "$status" != DONE ]; then
    # Codex's own failure text comes first because it is the only thing here
    # that separates a transient failure from a capability one. stderr follows
    # as a fallback: it carries the CLI's complaints - a rejected flag, a
    # missing directory - which are the failures that produce no error event.
    if [ -n "$codex_error" ]; then
      printf '\n## Codex error\n\n```\n%s\n```\n' "$codex_error"
    else
      printf '\n## Codex error\n\nNo error event on the --json stream. Either codex never reached the API, or it exited without reporting why.\n'
    fi
    printf '\n## Working tree\n\nLeft uncommitted on purpose. Last 20 stderr lines:\n\n```\n'
    tail -20 "$report.stderr" 2>/dev/null || true
    printf '```\n'
  fi
} > "$report"
cp -- "$report" "$human_report" || die 'cannot write human-readable report; authoritative report retained in task directory'

# Notes accumulate rather than replace one another: a run can both time out and
# leave a survivor, and the old single-slot note reported only the second.
notes=""
[ "$timed_out" = yes ] && notes="$notes note=timed-out"
[ "$survivor" = yes ] && notes="$notes note=codex-may-still-be-running"
printf 'codex %s/%s status=%s exit=%s commits=%s..%s thread=%s report=%s%s\n' \
  "$model" "$effort" "$status" "$rc" "${base:0:7}" "${head:0:7}" "$thread_id" "$human_report" "$notes"

[ "$status" = DONE ]
