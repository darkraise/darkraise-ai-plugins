#!/usr/bin/env bash
# Runs one agy (Antigravity CLI) review seat: selects the judge row, runs agy in
# plan mode under a bound, proves it wrote nothing, and classifies the outcome.
#
# Usage: run-agy-review.sh --kind task|risk3|plan|final --cwd DIR --out FILE
#          (--prompt FILE | --base SHA) [--tier light|heavy] [--dry-run]
# Output: agy-judge <model>/<effort> status=<OK|FALLBACK|TIMEOUT|FAILED>
#           exit=<n> out=<path> evidence=<e>[ reason=<token>]
# Exit: 0 on OK or FALLBACK, 1 on TIMEOUT or FAILED, 2 on a usage error.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Tests point these at a fixture ladder, a stub gate and a short grace. Unset in
# production, where the shipped table and scripts/agy-gate are read.
LADDER="${AGY_REVIEW_LADDER:-$HERE/../reference/ladder.md}"
GATE="${AGY_REVIEW_GATE:-$HERE/agy-gate}"
GRACE="${AGY_REVIEW_GRACE:-60}"
TASK_SCHEMA="$HERE/../criteria/codex-review-schema.json"
PLAN_SCHEMA="$HERE/../criteria/codex-plan-review-schema.json"
FINAL_SCHEMA="$HERE/../criteria/agy-final-review-schema.json"
FINAL_CRITERIA="$HERE/../criteria/codex-final-review.md"
. "$HERE/lib/worktree-snapshot.sh"
. "$HERE/lib/executor-session.sh"
. "$HERE/lib/native-path.sh"

die() { printf 'run-agy-review: %s\n' "$1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v timeout >/dev/null 2>&1 || die "GNU timeout is required but not on PATH"

kind=""; cwd=""; out=""; prompt=""; base=""; tier=""; dry_run=false
while [ $# -gt 0 ]; do
  case "$1" in
    --kind|--cwd|--out|--prompt|--base|--tier) [ $# -ge 2 ] || die "$1 needs a value" ;;
  esac
  case "$1" in
    --kind) kind="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --prompt) prompt="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --tier) tier="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$kind" in
  task|risk3) [ -n "$prompt" ] || die "--kind $kind requires --prompt"; kind=task ;;
  plan) [ -n "$prompt" ] || die "--kind plan requires --prompt" ;;
  final) [ -n "$base" ] || die "--kind final requires --base" ;;
  *) die "--kind must be task, risk3, plan or final" ;;
esac
case "$tier" in
  "") tier=heavy ;;
  light|heavy) [ "$kind" = task ] || die "--tier applies only to --kind task or risk3" ;;
  *) die "--tier must be light or heavy" ;;
esac
[ -n "$cwd" ] || die "--cwd is required"
[ -n "$out" ] || die "--out is required"
[ -d "$cwd" ] || die "--cwd is not a directory: $cwd"
[ -d "$(dirname "$out")" ] || die "--out directory not found: $(dirname "$out")"
[[ "$GRACE" =~ ^[0-9]+$ ]] || die "AGY_REVIEW_GRACE must be whole seconds: $GRACE"

case "$kind" in
  task) schema="$TASK_SCHEMA" ;;
  plan) schema="$PLAN_SCHEMA" ;;
  final) schema="$FINAL_SCHEMA" ;;
esac
[ -r "$schema" ] || die "review schema not found: $schema"

# Resolved before anything runs: agy runs in --cwd, while every file is read
# back from here.
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
cwd="$(cd "$cwd" && pwd)"
if [ -n "$prompt" ]; then
  [ -r "$prompt" ] || die "--prompt is not readable: $prompt"
  prompt="$(cd "$(dirname "$prompt")" && pwd)/$(basename "$prompt")"
fi

judge=$(awk '
  $0 == "```agy-judge" { f = 1; next }
  f && $0 == "```" { exit }
  f && NF { print }
' "$LADDER")
[ -n "$judge" ] || die "the agy-judge block is missing from $LADDER"
pref_model=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $1}')
pref_effort=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $2}')
back_model=$(printf '%s\n' "$judge" | tail -1 | awk '{print $1}')
back_effort=$(printf '%s\n' "$judge" | tail -1 | awk '{print $2}')
secs_of() { printf '%s\n' "$judge" | awk -v m="$1" -v e="$2" '$1 == m && $2 == e {print $3; exit}'; }

evidence=none
status() { # status <model> <effort> <state> <exit> [reason]
  printf 'agy-judge %s/%s status=%s exit=%s out=%s evidence=%s%s\n' \
    "$1" "$2" "$3" "$4" "$out" "$evidence" "${5:+ reason=$5}"
}

rm -f "$out" "$out.wrote"

# Only `usable` is read, never the review surface, so a run works while the
# policy's trust.review is still pending: that is how the surface gets trusted.
gate_line=$(bash "$GATE" 2>/dev/null | tail -1 | tr -d '\r')
if [[ "$gate_line" != *" usable=true "* ]]; then
  gate_reason=$(sed -n 's/.* reason=\([^ ]*\).*/\1/p' <<<"$gate_line")
  status none none FAILED 0 gate
  printf 'run-agy-review: agy is off for this session (%s)\n' "${gate_reason:-no gate answer}" >&2
  exit 1
fi

if [ "$tier" = light ]; then
  model="$back_model"; effort="$back_effort"
else
  model="$pref_model"; effort="$pref_effort"
  # Fails closed: a line that does not say claude=on keeps Claude out.
  if [[ "$model" == claude-* && "$gate_line" != *" claude=on "* ]]; then
    model="$back_model"; effort="$back_effort"; evidence=claude-off
  fi
fi
secs=$(secs_of "$model" "$effort")
[ -n "$secs" ] || die "no timeout for $model/$effort in the agy-judge block"

if [ "$dry_run" = true ]; then
  printf 'would-run:\n'
  jq -nc --arg kind "$kind" --arg cwd "$cwd" --arg model "$model" --arg effort "$effort" \
    --arg schema "$schema" --argjson seconds "$secs" \
    '{kind:$kind, cwd:$cwd, model:$model, effort:$effort, schemaPath:$schema,
      mode:"plan", timeoutSeconds:$seconds}'
  status "$model" "$effort" OK 0
  exit 0
fi

if ! command -v agy >/dev/null 2>&1; then
  status "$model" "$effort" FAILED 0 error
  printf 'run-agy-review: agy is not on PATH\n' >&2
  exit 1
fi

# The final round ships no prompt of its own: its criteria and the branch diff
# are written next to --out. Headless plan mode denies every shell command, so
# a prompt that sent agy to run git would come back with no review.
if [ "$kind" = final ]; then
  if ! git -C "$cwd" diff "$base...HEAD" > "$out.diff" 2> "$out.diff.err"; then
    status "$model" "$effort" FAILED 0 error
    printf 'run-agy-review: cannot diff %s...HEAD in %s\n' "$base" "$cwd" >&2
    exit 1
  fi
  prompt="$out.prompt"
  {
    cat "$FINAL_CRITERIA"
    printf '\n## The diff under review\n\n'
    printf '%s\n' '```diff'
    cat "$out.diff"
    printf '%s\n' '```'
  } > "$prompt" || die "cannot write the final-review prompt: $prompt"
fi

snapdir=$(mktemp -d) || die "cannot create a snapshot directory"
agy_pid=''
cleanup() {
  [ -z "$agy_pid" ] || kill -TERM -- "-$agy_pid" 2>/dev/null
  rm -rf "$snapdir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# The Gemini API refuses an integer enum before it generates anything, so agy
# gets a copy whose scores are bounded by minimum and maximum instead; answers
# are still checked against the shipped schema below.
agy_schema="$snapdir/$(basename "$schema")"
if ! jq 'walk(if type == "object" and .type == "integer" and (.enum | type) == "array"
    then (. + {minimum: (.enum | min), maximum: (.enum | max)} | del(.enum)) else . end)' \
    < "$schema" > "$agy_schema" 2>/dev/null; then
  status "$model" "$effort" FAILED 0 error
  printf 'run-agy-review: cannot derive the agy schema from %s\n' "$schema" >&2
  exit 1
fi

# Plan mode is the agy-side promise; this is the proof. The stash list is read
# separately because refs/stash is not in the worktree snapshot.
take_state() { # take_state <name>
  dr_snapshot "$cwd" "$snapdir/$1.json" || return 1
  git -C "$cwd" stash list --format='%H' 2>/dev/null | tr -d '\r' > "$snapdir/$1.stash"
}
if ! take_state before; then
  status "$model" "$effort" FAILED 0 error
  printf 'run-agy-review: cannot snapshot %s, so a write could not be detected\n' "$cwd" >&2
  exit 1
fi

# The prompt travels as a file the pointer names, never as an argument: a
# review prompt carrying a diff can exceed the 32,767-character Windows
# CreateProcess limit.
pointer="Your complete instructions are in $(dr_native_path "$prompt"). Read the whole file first and follow it."

run_row() { # run_row <model> <effort> <seconds> <log-prefix>; sets agy_rc
  local args=(--mode plan --output-format json --json-schema "$(dr_native_path "$agy_schema")"
    --model "$1" --effort "$2" --add-dir "$(dr_native_path "$(dirname "$prompt")")"
    --print-timeout "${3}s" -p "$pointer")
  # Job control is off in a script, so setsid execs in place: the job's pid is
  # also the process group id of agy and everything it starts.
  (
    cd "$cwd" || exit 1
    if command -v setsid >/dev/null 2>&1; then
      exec setsid timeout -k 10 $(($3 + GRACE)) agy "${args[@]}" < /dev/null > "$4.stdout" 2> "$4.stderr"
    else
      exec timeout -k 10 $(($3 + GRACE)) agy "${args[@]}" < /dev/null > "$4.stdout" 2> "$4.stderr"
    fi
  ) &
  agy_pid=$!
  wait "$agy_pid"
  agy_rc=$?
  kill -TERM -- "-$agy_pid" 2>/dev/null
  agy_pid=''
}

wrote_check() { # wrote_check; succeeds when the run changed nothing
  take_state after || { printf 'snapshot\n' > "$out.wrote"; return 1; }
  {
    jq -rn --slurpfile b "$snapdir/before.json" --slurpfile a "$snapdir/after.json" '
      def idx: reduce .files[] as $f ({}; .[$f.path] = $f);
      ($b[0] | idx) as $x | ($a[0] | idx) as $y |
      (($x | keys) + ($y | keys) | unique)[] | select($x[.] != $y[.])' | tr -d '\r'
    [ "$(jq -r .head < "$snapdir/before.json")" = "$(jq -r .head < "$snapdir/after.json")" ] || echo HEAD
    cmp -s "$snapdir/before.stash" "$snapdir/after.stash" || echo stash
  } > "$out.wrote"
  [ -s "$out.wrote" ] && return 1
  rm -f "$out.wrote"
}

# 429 only as a whole number: a sha, a UUID or a line number can carry those
# digits, and a false quota turns agy off for the rest of the session.
is_quota() { grep -qiE 'quota|rate.?limit|RESOURCE_EXHAUSTED|(^|[^[:alnum:]])429([^[:alnum:]]|$)' <<<"$1"; }

classify() { # classify <model> <log-prefix>; sets result and reason (empty when the answer is usable)
  local outer=no raw=no err finished ok=yes cause stderr_cause='' epoch=''
  [ "$agy_rc" -eq 124 ] || [ "$agy_rc" -eq 137 ] && outer=yes
  if jq -se 'length == 1 and (.[0] | type == "object")' < "$2.stdout" >/dev/null 2>&1; then
    result=$(jq -c . < "$2.stdout")
  else
    raw=yes result='{}'
  fi
  err=$(jq -r '.error // ""' <<<"$result" | tr -d '\r')
  finished=$(jq -r '.finished_reason // ""' <<<"$result" | tr -d '\r')
  { [ "$agy_rc" -eq 0 ] && [ "$(jq -r '.status // ""' <<<"$result" | tr -d '\r')" != ERROR ]; } || ok=no
  if [ "$finished" = print_timeout ] || [ "$outer" = yes ]; then reason=timeout; return; fi
  # A run that ended cleanly with one JSON object is never scanned: its text is
  # the model's own review and may well mention a quota.
  cause=$err
  if [ -z "$cause" ] && { [ "$ok" = no ] || [ "$raw" = yes ]; }; then
    [ "$raw" = no ] || cause=$(tail -20 "$2.stdout" 2>/dev/null | tr -d '\r')
    stderr_cause=$(tail -20 "$2.stderr" 2>/dev/null | tr -d '\r')
  fi
  if is_quota "$cause"; then
    reason=quota
    local reset_re='Resets in (([0-9]+)d)?(([0-9]+)h)?(([0-9]+)m)?(([0-9]+)s)?'
    if [[ "$cause" =~ $reset_re ]] && [ -n "${BASH_REMATCH[1]}${BASH_REMATCH[3]}${BASH_REMATCH[5]}${BASH_REMATCH[7]}" ]; then
      epoch=$(( $(date -u +%s) + 10#${BASH_REMATCH[2]:-0} * 86400 + 10#${BASH_REMATCH[4]:-0} * 3600 \
        + 10#${BASH_REMATCH[6]:-0} * 60 + 10#${BASH_REMATCH[8]:-0} ))
    fi
    # Antigravity counts Claude and Gemini against separate limits, so a quota
    # marks only the family that hit it.
    if [[ "$1" == claude-* ]]; then
      executor_session_mark_fallback_off agy "$epoch"
    else
      executor_session_mark_off agy quota "$epoch"
    fi
    return
  fi
  # stderr can carry output of commands the model ran, so a quota seen only
  # there labels the run and marks nothing.
  if is_quota "$stderr_cause"; then reason=quota-stderr; return; fi
  if grep -qiE 'unknown model|model .* not (found|available|supported|recognized)' <<<"$cause"$'\n'"$stderr_cause"; then
    reason=refused; return
  fi
  if [ "$ok" = no ] || [ "$raw" = yes ]; then reason=error; return; fi
  if ! jq -e --argjson s "$(jq -c . < "$schema")" '
      . as $r | (.structured_output | type) == "object" and
      ((($s.required // []) - (.structured_output | keys)) | length == 0) and
      ([$s.properties // {} | to_entries[]
        | select((.value.enum | type) == "array")
        | select(.key as $k | .value.enum | index([$r.structured_output[$k]]) == null)] | length == 0)' \
      <<<"$result" >/dev/null 2>&1; then
    reason=schema; return
  fi
  if [ "$kind" = final ] && ! jq -e '.structured_output.review | type == "string" and test("\\S")' \
      <<<"$result" >/dev/null 2>&1; then
    reason=schema; return
  fi
  reason=''
}

write_out() {
  if [ "$kind" = final ]; then
    jq -r '.structured_output.review' <<<"$result" > "$out"
  else
    jq '.structured_output' <<<"$result" > "$out"
  fi
}

run_row "$model" "$effort" "$secs" "$out"
if ! wrote_check; then
  evidence=wrote
  status "$model" "$effort" FAILED "$agy_rc" wrote
  printf 'run-agy-review: agy changed the worktree; see %s\n' "$out.wrote" >&2
  exit 1
fi
classify "$model" "$out"
if [ -z "$reason" ]; then
  write_out; status "$model" "$effort" OK "$agy_rc"; exit 0
fi
if [ "$reason" = timeout ]; then
  status "$model" "$effort" TIMEOUT "$agy_rc" timeout; exit 1
fi

# The fallback is attempted at most once, and never when the row that just ran
# is already the fallback row.
if [ "$reason" = refused ] && { [ "$model" != "$back_model" ] || [ "$effort" != "$back_effort" ]; }; then
  printf 'run-agy-review: %s/%s refused; falling back to %s/%s\n' \
    "$model" "$effort" "$back_model" "$back_effort" >&2
  model="$back_model"; effort="$back_effort"
  secs=$(secs_of "$model" "$effort")
  run_row "$model" "$effort" "$secs" "$out.fallback"
  if ! wrote_check; then
    evidence=wrote
    status "$model" "$effort" FAILED "$agy_rc" wrote
    printf 'run-agy-review: agy changed the worktree; see %s\n' "$out.wrote" >&2
    exit 1
  fi
  classify "$model" "$out.fallback"
  if [ -z "$reason" ]; then
    write_out; status "$model" "$effort" FALLBACK "$agy_rc" refused; exit 0
  fi
  [ "$reason" != timeout ] || { status "$model" "$effort" TIMEOUT "$agy_rc" timeout; exit 1; }
fi

status "$model" "$effort" FAILED "$agy_rc" "$reason"; exit 1
