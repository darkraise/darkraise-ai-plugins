#!/usr/bin/env bash
# Runs one plan task on agy (the Antigravity CLI) and leaves behind a report in
# the implementer report format.
#
# The model and effort are validated against the ladder before anything is
# spawned: that is what keeps a typo from becoming a paid round trip.
#
# agy enforces its own deadline (--print-timeout). The outer `timeout` bound is
# that deadline plus AGY_TASK_GRACE seconds (default 60), the margin agy gets to
# return its partial output before it is killed. Tests shorten the margin so an
# outer timeout takes seconds; nothing else sets it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
SCHEMA="$HERE/agy-report-schema.json"
CONTRACT="$HERE/agy-task-contract.md"
# Tests point this at a stub gate. Unset in production, where scripts/agy-gate
# answers from this session's cache or probes agy.
GATE="${AGY_TASK_GATE:-$HERE/agy-gate}"
GRACE="${AGY_TASK_GRACE:-60}"
source "$HERE/lib/task-state.sh"
source "$HERE/lib/task-execution.sh"
source "$HERE/lib/executor-session.sh"
source "$HERE/lib/native-path.sh"

VALID_EFFORTS="low medium high"

die() { printf 'run-agy-task: %s\n' "$1" >&2; exit 2; }

block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

brief="" report="" model="" effort="" cwd="" timeout_s="" thread="" dry=0 prompt=""
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
  dr_task_open "$cwd" "$task_id" '' "$([ "$operation" = release ] && echo handed-back)" || die 'cannot open task for recovery'
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
[ -f "$CONTRACT" ] || die "contract not found: $CONTRACT"
# Every verdict this wrapper reports is parsed with jq. Without it the parse
# below would fall back to BLOCKED, which is indistinguishable from a real
# block: the controller would spend a rung and a second paid run to learn
# nothing. The durable phase distinguishes preflight failures from failures after execution.
command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v timeout >/dev/null 2>&1 || die "GNU timeout is required but not on PATH"

# Resolved once: reset pathspecs are repo-relative while these files are written
# caller-relative, and `git reset` on a non-matching path exits 0, so the miss
# would be silent.
case "$report" in /*|[A-Za-z]:*) ;; *) report="$(pwd)/$report" ;; esac
# Checked here rather than discovered at the first redirect: a bad report
# directory would otherwise print shell redirect errors, never run agy, and
# exit 1 - the code the skill defines as "agy ran and did not reach DONE",
# costing the controller a rung for a typo.
[ -d "$(dirname "$report")" ] || die "report directory not found: $(dirname "$report")"

block agy-assignment | awk '{print $2}' | sort -u | grep -qxF -- "$model" \
  || die "model is not a rung in agy-assignment: $model"
# Word-exact, mirroring the model check above. A containment test on the padded
# string admits a multi-word value like "medium high", which would then fail far
# downstream in the timeout lookup instead of here.
printf '%s\n' $VALID_EFFORTS | grep -qxF -- "$effort" \
  || die "invalid reasoning effort: $effort (valid: $VALID_EFFORTS)"

if [ -z "$timeout_s" ]; then
  timeout_s=$(block agy-timeout | awk -v k="$model/$effort" '$1 == k {print $2}')
  [ -n "$timeout_s" ] || die "no agy-timeout row for $model/$effort"
fi
# Whole seconds only. The value becomes agy's print timeout and the outer
# coreutils bound below; a value like "30m" makes the arithmetic below fail
# and the run is reported as BLOCKED - the exact opposite of what raising the
# timeout was meant to do.
printf '%s' "$timeout_s" | grep -qE '^[0-9]+$' || die "--timeout must be whole seconds: $timeout_s"
if [ -n "$review_round" ]; then
  [[ "$review_round" =~ ^[1-5]$ ]] && [ -n "$thread" ] || die '--review-round requires a resume and a round from 1 to 5'
fi

if [ "$dry" -eq 1 ]; then
  printf 'would-run:\n'
  jq -nc --arg model "$model" --arg effort "$effort" --argjson timeout "$timeout_s" --arg thread "$thread" \
    '{model:$model, effort:$effort, timeoutSeconds:$timeout,
      conversation:(if $thread == "" then null else $thread end)}'
  exit 0
fi

[ -n "$task_id" ] || die '--task-id is required'
command -v agy >/dev/null 2>&1 || die "agy is required but not on PATH"
# The controller reads the gate before choosing the lane; reading it again here
# keeps a lane that closed since then (a quota, a settings switch, a failed
# smoke gate) from reaching a paid turn.
gate_line=$(bash "$GATE" 2>/dev/null | tail -1 | tr -d '\r')
if [[ "$gate_line" != *" lane=true "* ]]; then
  gate_reason=$(sed -n 's/.* reason=\([^ ]*\).*/\1/p' <<<"$gate_line")
  die "agy lane is off for this session (${gate_reason:-no gate answer})"
fi
cwd="$(dr_canonical "$cwd")" || die 'cannot resolve worktree'
report="$(realpath -m -- "$report")" || die 'cannot resolve report path'
case "$report" in
  "$cwd"/*)
    case "$report" in "$cwd"/.dforge/*) ;; *) die 'report must be outside checkout or in ignored .dforge workspace' ;; esac
    git -C "$cwd" check-ignore -q -- "$report" || die 'report workspace is not ignored'
    [ -z "$(git -C "$cwd" ls-files -- "$report")" ] || die 'report cannot be tracked' ;;
esac
dr_task_open "$cwd" "$task_id" "$write_set" || die 'task preflight failed'
trap 'dr_task_unlock' EXIT
record="$DR_TASK_DIR/state.json"
phase="$(jq -r .phase < "$record")"
case "$phase" in ready|pending|complete) ;; *) die "task phase $phase requires explicit recovery" ;; esac
[ "$(jq -r '.released // false' < "$record")" = false ] || die 'task ownership was released; use a new task ID'
[ "$(git -C "$cwd" rev-parse HEAD)" = "$(jq -r .expected_head < "$record")" ] || die 'HEAD drift requires reconciliation'
before_snapshot="$DR_TASK_DIR/before.json"
if [ "$phase" != ready ]; then
  jq '.pending // .baseline' < "$record" > "$before_snapshot" && dr_task_assert_snapshot "$before_snapshot" || die 'pending/index/worktree drift requires reconciliation'
fi
if [ -n "$thread" ]; then
  jq -e --arg thread "$thread" --arg model "$model" --arg effort "$effort" \
    '.thread == $thread and .model == $model and .effort == $effort' < "$record" >/dev/null || die 'resume thread/model/effort does not match task record'
fi
if [ -n "$review_round" ]; then
  [ "$review_round" -ge "$(jq -r .review_rounds < "$record")" ] || die 'review round cannot move backwards'
fi
dr_snapshot "$cwd" "$before_snapshot" || die 'cannot snapshot worktree'
human_report="$report"
attempt="$(jq '.attempts | length + 1' < "$record")"
report="$DR_TASK_DIR/attempt-$attempt.md"
prompt="$DR_TASK_DIR/prompt/attempt-$attempt.md"
dr_task_update '.model = $model | .effort = $effort | .baseline = $snapshot[0] | .candidate = null |
  .attempts += [{number:$attempt,model:$model,effort:$effort,resume:$resume,prior_thread:.thread}] |
  .review_rounds = (if $review_round == "" then .review_rounds else ($review_round | tonumber) end) |
  .artifacts = {report:$report,prompt:$prompt,result:($report + ".json"),last:($report + ".last.json"),stderr:($report + ".stderr")}' \
  --arg model "$model" --arg effort "$effort" --arg resume "$thread" --argjson attempt "$attempt" \
  --arg review_round "$review_round" \
  --arg report "$report" --arg prompt "$prompt" --slurpfile snapshot "$before_snapshot" || die 'cannot persist attempt'

result="$report.json"
last="$report.last.json"

# agy is given access to the prompt directory, so it holds nothing but prompt
# files; the task record stays one level up, out of its reach.
mkdir -p "$DR_TASK_DIR/prompt" || die 'cannot create prompt directory'
{
  cat "$brief"
  # The host repo may have either file or neither. Inlining beats assuming:
  # this plugin ships to arbitrary repositories, and writing a conventions file
  # would change the user's own sessions too.
  for f in CLAUDE.md AGENTS.md; do
    if [ -f "$cwd/$f" ]; then
      printf '\n\n## Repository conventions (%s)\n\n' "$f"
      cat "$cwd/$f"
    fi
  done
  printf '\n\n'
  cat "$CONTRACT"
} > "$prompt" || die "cannot write prompt file: $prompt"

# --show-prefix avoids comparing native Windows paths with MSYS paths.
prefix=$(git -C "$cwd" rev-parse --show-prefix) || die "not a git repository: $cwd"
[ -z "$prefix" ] || die "cwd must be the repository root, but sits under $prefix"
base=$(git -C "$cwd" rev-parse HEAD) || die "cannot resolve HEAD in $cwd"

# The interrupted-run guard and the unlock both live here, because the EXIT
# trap is the only thing that releases the worktree lock.
cleanup() {
  if [ "$(jq -r .phase < "$record" 2>/dev/null)" = running ]; then
    dr_task_update '.processes = []' && dr_task_block 'execution interrupted; reconcile the recorded snapshot' || true
  fi
  dr_task_unlock
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# agy can exit without printing a verdict. Left in place, a previous run's
# verdict would be read as this one's - guaranteed on every resume round, which
# reuses the same report path - and the wrapper would commit under a stale
# subject it never earned. $report is cleared for the same reason: a die path
# below (a failed add or commit) leaves the previous round's report in place,
# complete and carrying `status: DONE`, while the exit-2 recovery text tells the
# controller no report was written. rm -f succeeds on a missing file but can
# fail on a locked one, so the clear is verified rather than assumed.
rm -f "$last" "$result" "$report"
[ ! -f "$last" ] || die "could not clear stale verdict file: $last"

dr_task_update '.phase = "running" | .processes = []' || die 'cannot persist running phase'

# The prompt travels as a file the pointer names, never as an argument: a brief
# plus conventions plus the contract can exceed the 32,767-character Windows
# CreateProcess limit.
pointer="Your complete instructions are in $(dr_native_path "$prompt"). Read the whole file first and follow it."
agy_args=(--output-format json --json-schema "$(dr_native_path "$SCHEMA")" --model "$model" --effort "$effort"
  --dangerously-skip-permissions --add-dir "$(dr_native_path "$DR_TASK_DIR/prompt")" --print-timeout "${timeout_s}s")
[ -n "$thread" ] && agy_args+=(--conversation "$thread")
agy_args+=(-p "$pointer")

# Job control is off in a script, so setsid execs in place: the job's pid is
# also the process group id of agy and everything it starts.
(
  cd "$cwd" || exit 1
  if command -v setsid >/dev/null 2>&1; then
    exec setsid timeout -k 10 $((timeout_s + GRACE)) agy "${agy_args[@]}" < /dev/null > "$result" 2> "$report.stderr"
  else
    exec timeout -k 10 $((timeout_s + GRACE)) agy "${agy_args[@]}" < /dev/null > "$result" 2> "$report.stderr"
  fi
) &
agy_pid=$!
wait "$agy_pid"
agy_rc=$?

# An agy that died before printing leaves no object behind, and every jq below
# would then fail and take the runner with it. One guard here covers all of them.
jq -se 'length == 1 and (.[0] | type == "object")' < "$result" >/dev/null 2>&1 || printf '{}\n' > "$result"

# The verdict file. Lines below parse $last for status, summary and
# commit_subject, so writing it here is what keeps the runner able to commit.
# No file at all for a missing verdict: a missing $last is what the verdict
# block below reads as BLOCKED.
jq -c '.structured_output | select(type == "object")' < "$result" > "$last" 2>/dev/null
[ -s "$last" ] || rm -f "$last"

# A run that never reached agy discovers no conversation. The recorded one is
# kept then, or the next --resume would be refused for a thread named "unknown".
thread_id=$(jq -r '.conversation_id // empty' < "$result" | tr -d '\r')
if [ -n "$thread_id" ]; then
  dr_task_update '.thread = $thread' --arg thread "$thread_id" || die 'cannot persist task thread'
else
  thread_id="${thread:-$(jq -r '.thread // "unknown"' < "$record")}"
fi

agy_error=$(jq -r '.error // ""' < "$result" | tr -d '\r')
rc=0
{ [ "$agy_rc" -eq 0 ] && [ "$(jq -r '.status // ""' < "$result" | tr -d '\r')" != ERROR ]; } || rc=1

status=BLOCKED
summary=""
subject=""
discovered=""
assumptions=""
if [ -f "$last" ]; then
  status=$(jq -r '.status // "BLOCKED"' < "$last" 2>/dev/null | tr -d '\r')
  [ -n "$status" ] || status=BLOCKED
  summary=$(jq -r '.summary // ""' < "$last" 2>/dev/null | tr -d '\r')
  subject=$(jq -r '.commit_subject // ""' < "$last" 2>/dev/null | tr -d '\r')
  discovered=$(jq -r '(.discovered_issues // [])[] | "- " + .' < "$last" 2>/dev/null | tr -d '\r')
  assumptions=$(jq -r '(.assumptions // [])[] | "- " + .' < "$last" 2>/dev/null | tr -d '\r')
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
  printf -- '- executor: agy %s / %s\n' "$model" "$effort"
  printf -- '- thread: %s\n' "$thread_id"
  printf -- '- status: %s\n' "$status"
  printf -- '- exit: %s\n' "$rc"
  printf -- '- commits: %s..%s\n' "${base:0:7}" "${head:0:7}"
  [ "$committed" = empty ] && printf -- '- note: DONE with an empty diff; nothing was committed\n'
  printf '\n## Summary\n\n%s\n' "$summary"
  printf '\n## Discovered issues (not fixed)\n\n%s\n' "${discovered:-None}"
  printf '\n## Assumptions made\n\n%s\n' "${assumptions:-None}"
  if [ "$status" = NEEDS_CONTEXT ]; then
    printf '\n## Questions\n\n'
    jq -r '.questions[]? | "- " + .' < "$last" 2>/dev/null | tr -d '\r' || true
  fi
  if [ "$status" != DONE ]; then
    # agy's own failure text comes first because it is the only thing here
    # that separates a transient failure from a capability one. stderr follows
    # as a fallback: it carries agy's own complaints, which are the failures
    # that leave no error in its result.
    printf '\n## Agy error\n\n```\n%s\n```\n' "${agy_error:-agy returned no error text}"
    printf '\n## Working tree\n\nLeft uncommitted on purpose. Last 20 stderr lines:\n\n```\n'
    tail -20 "$report.stderr" 2>/dev/null || true
    printf '```\n'
  fi
} > "$report"
cp -- "$report" "$human_report" || die 'cannot write human-readable report; authoritative report retained in task directory'

printf 'agy %s/%s status=%s exit=%s commits=%s..%s thread=%s report=%s\n' \
  "$model" "$effort" "$status" "$rc" "${base:0:7}" "${head:0:7}" "$thread_id" "$human_report"

[ "$status" = DONE ]
