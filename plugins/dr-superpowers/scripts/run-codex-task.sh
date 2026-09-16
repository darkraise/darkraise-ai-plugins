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
command -v timeout >/dev/null 2>&1 || die "GNU timeout is required but not on PATH"

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

# Every per-invocation field is rebuilt here, including on resume: the client
# starts a fresh thread unless resumeThreadId is set, and a resumed thread must
# carry the same model and effort the record pins.
#
# --rawfile, not --arg "$(cat ...)": a task prompt is a brief plus CLAUDE.md
# plus a contract, and passing it as an argument blows the 32,767-character
# Windows CreateProcess limit.
build_request() { # build_request; echoes the request JSON
  jq -nc \
    --arg cwd "$cwd" --arg model "$model" --arg effort "$effort" \
    --rawfile prompt "${prompt:-/dev/null}" --arg thread "${thread:-}" \
    --arg schema "$SCHEMA" --argjson deadline "$(( timeout_s * 1000 ))" \
    '{op:"turn", kind:"task", cwd:$cwd, model:$model, effort:$effort,
      prompt:$prompt, schemaPath:$schema, sandbox:"workspace-write",
      resumeThreadId:(if $thread == "" then null else $thread end),
      persistThread:true, threadName:null, deadlineMs:$deadline}'
}

if [ "$dry" -eq 1 ]; then
  printf 'would-run:\n'
  build_request
  exit 0
fi

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

# The only child is node, which exits when the client does, and the client reaps
# the broker it caused to exist. Nothing here has a process group to signal - but
# the interrupted-run guard and the unlock both stay, because the EXIT trap is
# still the only thing that releases the worktree lock.
cleanup() {
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

# The client owns the deadline, the interrupt and the broker reaper, so there is
# no process group for this script to create, poll or signal: node is a direct
# child that exits on its own.
#
# The plugin root is resolved here rather than beside build_request, so that
# --dry-run returns above without needing an enabled plugin. scripts/codex-plugin
# owns the locator and the version allowlist; this script never names the codex
# executable.
plugin_line=$(bash "$HERE/codex-plugin") || die "the codex plugin is not usable: $plugin_line"
plugin_root=${plugin_line#*root=}

dr_task_update '.phase = "running" | .processes = []' || die 'cannot persist running phase'

result=$(build_request | timeout $((timeout_s + 60)) node "$HERE/lib/codex-client.mjs" "$plugin_root" 2>"$report.stderr")
# A node that died before printing leaves $result empty, and every jq below would
# then fail and take the runner with it. One guard here covers all of them.
[ -n "$result" ] || result='{}'
printf '%s\n' "$result" > "$jsonl"

# The report the verdict is read from. The client returns the model's structured
# output as finalMessage; lines below parse $last for status, summary and
# commit_subject, so writing it here is what keeps the runner able to commit.
# -j, not -r, and no file at all for an empty message: -r would leave a one-byte
# file whose parse yields status "", while a missing $last is what the verdict
# block below has always read as BLOCKED.
jq -j '.finalMessage // ""' <<<"$result" > "$last"
[ -s "$last" ] || rm -f "$last"

discovered_thread=$(jq -r '.threadId // empty' <<<"$result")
if [ -n "$discovered_thread" ]; then
  dr_task_update '.thread = $thread' --arg thread "$discovered_thread" \
    || die 'cannot persist thread'
fi

# The client reaps the broker it caused to exist. Recording the outcome makes a
# leak visible in the task record rather than only in a process list. Task 10
# Step 5 already guarantees $result holds an object, so the jq below cannot be
# handed an empty string; the `if` still defaults a missing key to false.
dr_task_update '.reaped = $reaped' \
  --argjson reaped "$(jq -r 'if .reaped == true then true else false end' <<<"$result" 2>/dev/null || echo false)" \
  || die 'cannot persist reap outcome'

timed_out=no
[ "$(jq -r '.timedOut' <<<"$result")" = true ] && timed_out=yes
rc=0
[ "$(jq -r '.ok' <<<"$result")" = true ] || rc=1
[ "$timed_out" = yes ] && rc=124
survivor=no

# Event field naming has varied across Codex releases, so match on any of the
# shapes rather than pinning one that a later version may rename.
thread_id=$(jq -r 'select(type=="object")
  | (.thread_id // .threadId // .session_id // .sessionId // empty)' \
  "$jsonl" 2>/dev/null | head -1)
[ -n "$thread_id" ] || thread_id="${thread:-unknown}"
dr_task_update '.thread = $thread' --arg thread "$thread_id" || die 'cannot persist task thread'

# The client classifies the failure, so this is where the controller reads it.
# `reason` separates quota from refusal from timeout from a plugin fault, and
# `stderr` carries whatever text came back. Without this the task report says
# only "exit 1", which reads as a model that gave up rather than one that was
# never reached.
codex_error=$(jq -r '
  [ (if .reason then "reason=" + .reason else empty end),
    (if .refusal == true then "refusal=true" else empty end),
    (if .quota == true then "quota=true" else empty end),
    (if .timedOut == true then "timedOut=true" else empty end),
    (.stderr // "" | select(. != "")) ]
  | join("\n")' <<<"$result" 2>/dev/null || true)

status=BLOCKED
summary=""
subject=""
discovered=""
assumptions=""
if [ -f "$last" ]; then
  status=$(jq -r '.status // "BLOCKED"' "$last" 2>/dev/null || echo BLOCKED)
  summary=$(jq -r '.summary // ""' "$last" 2>/dev/null || true)
  subject=$(jq -r '.commit_subject // ""' "$last" 2>/dev/null || true)
  discovered=$(jq -r '(.discovered_issues // [])[] | "- " + .' "$last" 2>/dev/null || true)
  assumptions=$(jq -r '(.assumptions // [])[] | "- " + .' "$last" 2>/dev/null || true)
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
  printf '\n## Summary\n\n%s\n' "$summary"
  printf '\n## Discovered issues (not fixed)\n\n%s\n' "${discovered:-None}"
  printf '\n## Assumptions made\n\n%s\n' "${assumptions:-None}"
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
