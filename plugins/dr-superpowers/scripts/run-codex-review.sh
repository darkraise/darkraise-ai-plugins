#!/usr/bin/env bash
# Runs one Codex review seat: selects the judge rung, bounds the run, and
# classifies the outcome.
#
# Both Claude-hosted seats call this instead of composing a codex command
# themselves. An earlier design left the selection and fallback rules in prose,
# and the runtime never reached the paragraph describing them: the fallback was
# unreachable code written in English. Anything a seat must decide lives here,
# where a test can reach it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
SCHEMA="$HERE/../criteria/codex-review-schema.json"
# Tests point this at a stub roster. Unset in production, where the real
# detector runs and its auth probe is the usability guard.
ROSTER="${CODEX_REVIEW_ROSTER:-$HERE/detect-executors.sh}"

die() { printf 'run-codex-review: %s\n' "$1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v timeout >/dev/null 2>&1 || die "GNU timeout is required but not on PATH"

kind=""; cwd=""; out=""; prompt=""; base=""; dry_run=false
while [ $# -gt 0 ]; do
  case "$1" in
    --kind|--cwd|--out|--prompt|--base) [ $# -ge 2 ] || die "$1 needs a value" ;;
  esac
  case "$1" in
    --kind) kind="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --prompt) prompt="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$kind" in
  risk3) [ -n "$prompt" ] || die "--kind risk3 requires --prompt" ;;
  final) [ -n "$base" ] || die "--kind final requires --base" ;;
  *) die "--kind must be risk3 or final" ;;
esac
[ -n "$cwd" ] || die "--cwd is required"
[ -n "$out" ] || die "--out is required"
[ -d "$cwd" ] || die "--cwd is not a directory: $cwd"
[ -d "$(dirname "$out")" ] || die "--out directory not found: $(dirname "$out")"

# Resolve before anything runs. The seat runs inside a subshell that cd's to
# --cwd, while the output is read back from here, so a relative path would be
# written into the worktree and then reported missing.
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
cwd="$(cd "$cwd" && pwd)"
[ "$kind" != risk3 ] || [ -r "$prompt" ] || die "--prompt is not readable: $prompt"
[ "$kind" != risk3 ] || [ -r "$SCHEMA" ] || die "review schema not found: $SCHEMA"
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

if [ "$listed" = true ]; then
  model="$pref_model"; effort="$pref_effort"
else
  model="$back_model"; effort="$back_effort"
fi
secs=$(secs_of "$model" "$effort")
[ -n "$secs" ] || die "no timeout for $model/$effort in the codex-judge block"

# The command each kind runs. risk3 uses plain `codex exec` with this plugin's
# own schema, never `codex exec review`, which imposes its own report shape -
# the three risk-3 judges must return comparable criteria.
build_argv() { # build_argv <model> <effort>
  if [ "$kind" = risk3 ]; then
    printf '%s\n' codex exec -s read-only -m "$1" -c "model_reasoning_effort=$2" \
      --output-schema "$SCHEMA" -o "$out" -C "$cwd"
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

# Valid output is defined per kind. risk3 must parse as the criteria the other
# two judges return; final has no schema and only has to be non-empty.
valid_output() {
  if [ "$kind" = risk3 ]; then
    jq -e 'has("spec_verdict") and has("task_quality") and has("cannot_verify")' \
      "$out" >/dev/null 2>&1
  else
    [ -s "$out" ]
  fi
}

# A refusal is the one failure a different model repairs. An expired token, an
# exhausted quota, a bad working directory and a cancelled run are not refusals:
# the fallback would fail identically and would cost a second full round.
#
# Both streams are searched. Codex reports API failures as events on its JSON
# stream, which is stdout - see external-executor.md, "Read `## Codex error` in
# the report, not `<report>.stderr`" - while stderr carries the CLI's own
# complaints. A model refusal can arrive on either, and searching only stderr
# would make this whole rule unreachable for the API-level case.
is_refusal() { # is_refusal <log-prefix>
  grep -qiE '(unsupported|unknown|invalid|not (supported|available|found)).*(model|effort)|(model|effort).*(unsupported|unknown|invalid|not (supported|available|found))|http 400|status 400' \
    "$1.stdout" "$1.stderr" 2>/dev/null
}

refusal_line() { # refusal_line <log-prefix>
  cat "$1.stderr" "$1.stdout" 2>/dev/null | grep -m1 . | tr -d '\r'
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
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
fi

status "$model" "$effort" FAILED "$rc"; exit 1
