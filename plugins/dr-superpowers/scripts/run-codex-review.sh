#!/usr/bin/env bash
# Runs one Codex review seat: selects the judge rung, bounds the run, and
# classifies the outcome.
#
# Every Claude-hosted Codex review seat calls this instead of composing a codex
# command itself. An earlier design left the selection and fallback rules in
# prose, and the runtime never reached the paragraph describing them: the
# fallback was unreachable code written in English. Anything a seat must decide
# lives here, where a test can reach it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
TASK_SCHEMA="$HERE/../criteria/codex-review-schema.json"
PLAN_SCHEMA="$HERE/../criteria/codex-plan-review-schema.json"
# Tests point this at a stub roster. Unset in production, where the real
# detector runs and its auth probe is the usability guard.
ROSTER="${CODEX_REVIEW_ROSTER:-$HERE/detect-executors.sh}"
# Tests point this at a stub gate. Unset in production, where scripts/codex-gate
# answers from this session's cache or probes the codex plugin.
GATE="${CODEX_REVIEW_GATE:-$HERE/codex-gate}"
. "$HERE/lib/codex-session.sh"

die() { printf 'run-codex-review: %s\n' "$1" >&2; exit 2; }

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

# task is the name scripts/review-route prints; risk3 is the same seat under
# its sub-project 7 name, kept so earlier callers keep working.
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

case "$kind" in
  task) schema="$TASK_SCHEMA" ;;
  plan) schema="$PLAN_SCHEMA" ;;
  *) schema="" ;;
esac

# Resolve before anything runs. The seat runs inside a subshell that cd's to
# --cwd, while the output is read back from here, so a relative path would be
# written into the worktree and then reported missing.
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
cwd="$(cd "$cwd" && pwd)"
[ -z "$schema" ] || [ -r "$prompt" ] || die "--prompt is not readable: $prompt"
[ -z "$schema" ] || [ -r "$schema" ] || die "review schema not found: $schema"
[ -z "$prompt" ] || prompt="$(cd "$(dirname "$prompt")" && pwd)/$(basename "$prompt")"

# The judge policy, first row preferred and last row the fallback.
judge=$(awk '
  $0 == "```codex-judge" { f = 1; next }
  f && $0 == "```" { exit }
  f && NF { print }
' "$LADDER")
[ -n "$judge" ] || die "the codex-judge block is missing from $LADDER"

pref_model=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $1}')
pref_effort=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $2}')
back_model=$(printf '%s\n' "$judge" | tail -1 | awk '{print $1}')
back_effort=$(printf '%s\n' "$judge" | tail -1 | awk '{print $2}')
secs_of() { printf '%s\n' "$judge" | awk -v m="$1" -v e="$2" '$1 == m && $2 == e {print $3; exit}'; }

# The session gate runs before the roster, on every kind and on a dry run: a
# Codex this session may not use is never selected or run. Only `usable` is
# read, never the review surface, so a shipping gate can still exercise an
# untrusted surface.
gate_line=$(bash "$GATE" 2>/dev/null); gate_rc=$?
gate_line=$(printf '%s\n' "$gate_line" | tail -1 | tr -d '\r')
if [ "$gate_rc" -ne 0 ] || [[ "$gate_line" != *" usable=true "* ]]; then
  gate_reason=$(sed -n 's/.* reason=\([^ ]*\).*/\1/p' <<<"$gate_line")
  [ "$gate_rc" -eq 0 ] || gate_reason="codex-gate exited $gate_rc"
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=unknown\n' "$out"
  printf 'run-codex-review: codex is off for this session (%s)\n' "${gate_reason:-no gate answer}" >&2
  exit 1
fi

# Selection. The catalog is a negative filter: a pair it does not advertise is
# never attempted, and every state that is not a positive match - no catalog, an
# unreadable one, one that lists nothing, one that lists other models - takes the
# fallback row. That is the owner's fail-closed rule, and null is deliberately
# not treated as [].
# Invoked through bash, not executed directly: core.filemode is false on some
# checkouts, so the detector can arrive at mode 100644 and a direct call would
# fail every seat with "no codex row".
roster=$(bash "$ROSTER" 2>/dev/null) || roster=""
codex_row=$(printf '%s' "$roster" | jq -c '.[]? | select(.id=="codex")' 2>/dev/null)
[ -n "$codex_row" ] || die "no codex row in the executor roster"

usable=$(printf '%s' "$codex_row" | jq -r '.usable')
if [ "$usable" != true ]; then
  reason=$(printf '%s' "$codex_row" | jq -r '.reason // "codex is not usable"')
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=unknown\n' "$out"
  printf 'run-codex-review: %s\n' "$reason" >&2
  exit 1
fi

advertised=$(printf '%s' "$codex_row" | jq -c '.advertised')
if [ "$advertised" = null ]; then
  evidence=unknown
  listed=false
else
  evidence=$(printf '%s' "$advertised" | jq -r '.fetched_at // "unknown"')
  listed=$(printf '%s' "$advertised" | jq --arg m "$pref_model" --arg e "$pref_effort" \
    '[.pairs[]? | select(.model == $m and .effort == $e)] | length > 0')
fi

# The light tier is the last row by definition: it is the known-good rung, so
# the catalog has nothing to veto, and it is already the fallback row, so the
# refusal branch below never retries it against itself.
if [ "$tier" = light ]; then
  model="$back_model"; effort="$back_effort"
elif [ "$listed" = true ]; then
  model="$pref_model"; effort="$pref_effort"
else
  model="$back_model"; effort="$back_effort"
fi
secs=$(secs_of "$model" "$effort")
[ -n "$secs" ] || die "no timeout for $model/$effort in the codex-judge block"

# The command each kind runs. task and plan use plain `codex exec` with this
# plugin's own schema, never `codex exec review`, which imposes its own report
# shape - a seat must return the criteria the Claude judges return.
build_argv() { # build_argv <model> <effort>
  if [ -n "$schema" ]; then
    printf '%s\n' codex exec -s read-only -m "$1" -c "model_reasoning_effort=$2" \
      --output-schema "$schema" -o "$out" -C "$cwd"
  else
    printf '%s\n' codex exec review --base "$base" -m "$1" -c "model_reasoning_effort=$2" \
      -o "$out"
  fi
}

if [ "$dry_run" = true ]; then
  printf 'would-run:\n'
  build_argv "$model" "$effort"
  printf 'codex-judge %s/%s status=OK exit=0 out=%s evidence=%s\n' \
    "$model" "$effort" "$out" "$evidence"
  exit 0
fi

# Valid output is defined per kind. task and plan must parse as their schema's
# keys; final has no schema and only has to be non-empty.
valid_output() {
  case "$kind" in
    task) jq -e 'has("spec_verdict") and has("task_quality") and has("cannot_verify")' \
      "$out" >/dev/null 2>&1 ;;
    plan) jq -e 'has("executability") and has("coherence") and has("coverage") and has("assumptions") and has("findings")' \
      "$out" >/dev/null 2>&1 ;;
    *) [ -s "$out" ] ;;
  esac
}

# A refusal is the one failure a different model repairs. An expired token, an
# exhausted quota, a bad working directory and a cancelled run are not refusals:
# the fallback would fail identically and would cost a second full round.
#
# Only error-shaped lines are searched, and only at column 0. Codex writes its
# whole session transcript - every file the model read, and the review text
# itself - to stderr, and the report to stdout: a 2026-09-14 `--kind final` run
# on this repository left 10,590 stderr lines carrying 20 matches for an
# unanchored search, because this plugin's own tests and prose quote refusal
# messages. Matching those would declare a refusal on a clean run and buy a
# second full round. Both streams are still read: an API-level refusal arrives
# as a JSON event, which can reach either.
REFUSAL='(unsupported|unknown|invalid|not (supported|available|found)).*(model|effort)|(model|effort).*(unsupported|unknown|invalid|not (supported|available|found))'

error_lines() { # error_lines <log-prefix>
  grep -hE '^ERROR:|^\{"type": ?"error"' "$1.stdout" "$1.stderr" 2>/dev/null
}

# grep -c, not -q: -q exits at the first match, and under pipefail the SIGPIPE it
# sends error_lines would read as "no match".
is_refusal() { # is_refusal <log-prefix>
  local n; n=$(error_lines "$1" | grep -ciE "$REFUSAL") || true
  [ "${n:-0}" -gt 0 ]
}

# An exhausted quota is not a refusal either: every model on the account hits
# the same limit. It turns Codex off for the rest of the session instead, so the
# next seat goes straight to its Claude judge.
QUOTA='usage limit|rate_limit_reached'

is_quota() { # is_quota <log-prefix>
  local n; n=$(error_lines "$1" | grep -ciE "$QUOTA") || true
  [ "${n:-0}" -gt 0 ]
}

# The same line the match came from, not merely the first line of stderr - that
# is the CLI banner, which would make every substitution read as "refused
# (OpenAI Codex v0.154.0)".
refusal_line() { # refusal_line <log-prefix>
  error_lines "$1" | grep -m1 . | tr -d '\r'
}

# Each attempt writes its own pair of logs. Sharing one would let the fallback's
# (usually empty) output overwrite the refusal that explains why the fallback
# ran at all, which is the line the ledger substitution quotes.
run_seat() { # run_seat <model> <effort> <seconds> <log-prefix>; echoes the exit code
  local argv=() line
  while IFS= read -r line; do argv+=("$line"); done < <(build_argv "$1" "$2")
  rm -f "$out"
  ( cd "$cwd" && timeout "$3" "${argv[@]}" >"$4.stdout" 2>"$4.stderr" \
      < "${prompt:-/dev/null}" )
  printf '%s' "$?"
}

status() { # status <model> <effort> <state> <exit>
  printf 'codex-judge %s/%s status=%s exit=%s out=%s evidence=%s\n' \
    "$1" "$2" "$3" "$4" "$out" "$evidence"
}

rc=$(run_seat "$model" "$effort" "$secs" "$out")

# Deadline expiry is tracked apart from every other non-zero exit: a hang and a
# refusal both exit non-zero, and only one of them is worth a second run.
if [ "$rc" -eq 124 ]; then
  status "$model" "$effort" TIMEOUT "$rc"; exit 1
fi

if [ "$rc" -eq 0 ] && valid_output; then
  status "$model" "$effort" OK "$rc"; exit 0
fi

if is_quota "$out"; then
  codex_session_mark_off quota
  status "$model" "$effort" FAILED "$rc"; exit 1
fi

# The fallback is attempted at most once, and never when the row that just ran
# is already the fallback row.
if is_refusal "$out" \
   && { [ "$model" != "$back_model" ] || [ "$effort" != "$back_effort" ]; }; then
  printf 'run-codex-review: %s/%s refused (%s); falling back to %s/%s\n' \
    "$model" "$effort" "$(refusal_line "$out")" "$back_model" "$back_effort" >&2
  back_secs=$(secs_of "$back_model" "$back_effort")
  rc=$(run_seat "$back_model" "$back_effort" "$back_secs" "$out.fallback")
  if [ "$rc" -eq 124 ]; then
    status "$back_model" "$back_effort" TIMEOUT "$rc"; exit 1
  fi
  if [ "$rc" -eq 0 ] && valid_output; then
    status "$back_model" "$back_effort" FALLBACK "$rc"; exit 0
  fi
  is_quota "$out.fallback" && codex_session_mark_off quota
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
fi

status "$model" "$effort" FAILED "$rc"; exit 1
