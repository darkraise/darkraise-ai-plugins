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

# The plugin root, resolved once. scripts/codex-plugin owns the locator and the
# version allowlist; this script never names the codex executable.
#
# A locator refusal is a FAILED seat, not a usage error: spec section 7 maps
# locate and version failures to the status line, and exiting 2 here would make
# a caller that reads the line see nothing at all.
if ! plugin_line=$(bash "$HERE/codex-plugin"); then
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=none\n' "$out"
  printf 'run-codex-review: %s\n' "$plugin_line" >&2
  exit 1
fi
plugin_root=${plugin_line#*root=}

# One seat run, through the plugin's client. The client owns the deadline, the
# interrupt and the broker reaper; this script owns the argv contract, the
# status line and the exit code.
#
# --rawfile, not --arg "$(cat ...)": a reviewer prompt carries a whole branch
# diff and passing it as an argument blows the 32,767-character Windows
# CreateProcess limit.
run_seat() { # run_seat <model> <effort> <seconds> <log-prefix>; echoes the result JSON
  local request
  request=$(jq -nc \
    --arg kind "$kind" --arg cwd "$cwd" --arg model "$1" --arg effort "$2" \
    --rawfile prompt "${prompt:-/dev/null}" --arg schema "${schema:-}" \
    --argjson deadline "$(( $3 * 1000 ))" \
    '{op:"turn", kind:$kind, cwd:$cwd, model:$model, effort:$effort,
      prompt:$prompt,
      schemaPath:(if $schema == "" then null else $schema end),
      sandbox:"read-only", resumeThreadId:null, persistThread:false,
      threadName:null, deadlineMs:$deadline}')
  printf '%s' "$request" | node "$HERE/lib/codex-client.mjs" "$plugin_root" 2>"$4.stderr"
}

# --kind final ships no --prompt of its own: the round is defined by the branch.
# Its criteria and its diff are composed here, because the plugin call that would
# otherwise do this - runAppServerReview - reads only model, threadName, target
# and delivery (codex.mjs:908-961) and answers in Codex's own report shape,
# discarding the criteria a seat has to return.
#
# There is no $base in the request: it is consumed here and nowhere else.
compose_final_prompt() { # compose_final_prompt; echoes the composed prompt path
  local file="$out.prompt" diff="$out.diff"
  git -C "$cwd" diff "$base...HEAD" > "$diff" 2>"$out.diff.err" || return 1
  {
    cat "$HERE/../criteria/codex-final-review.md"
    printf '\n## The diff under review\n\n'
    printf '%s\n' '```diff'
    cat "$diff"
    printf '%s\n' '```'
  } > "$file" || return 1
  printf '%s' "$file"
}

# The report is whatever the seat returned. Writing it here rather than in the
# client keeps the --out contract with bash, which owns it.
write_out() { # write_out <result-json>
  # -j, not -r: -r appends a newline, so an empty finalMessage would leave a
  # one-byte file that valid_output's -s test would call a review.
  jq -j '.finalMessage // ""' <<<"$1" > "$out"
}

status() { # status <model> <effort> <state> <exit>
  printf 'codex-judge %s/%s status=%s exit=%s out=%s evidence=%s\n' \
    "$1" "$2" "$3" "$4" "$out" "$evidence"
}

# The final round composes its prompt from the branch; every other kind was
# given one on argv. A failure here is a FAILED seat, not a usage error: the
# caller reads the status line and would otherwise see nothing at all.
if [ "$kind" = final ]; then
  if ! prompt=$(compose_final_prompt); then
    printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=none\n' "$out"
    printf 'run-codex-review: cannot diff %s...HEAD in %s\n' "$base" "$cwd" >&2
    exit 1
  fi
fi

result=$(run_seat "$model" "$effort" "$secs" "$out")
write_out "$result"
rc=0
[ "$(jq -r '.ok' <<<"$result")" = true ] || rc=1
[ "$(jq -r '.timedOut' <<<"$result")" = true ] && rc=124

if [ "$rc" -eq 124 ]; then
  status "$model" "$effort" TIMEOUT "$rc"; exit 1
fi

if [ "$rc" -eq 0 ] && valid_output; then
  status "$model" "$effort" OK "$rc"; exit 0
fi

if [ "$(jq -r '.quota' <<<"$result")" = true ]; then
  codex_session_mark_off quota
  status "$model" "$effort" FAILED "$rc"; exit 1
fi

# The fallback is attempted at most once, and never when the row that just ran
# is already the fallback row.
if [ "$(jq -r '.refusal' <<<"$result")" = true ] \
   && { [ "$model" != "$back_model" ] || [ "$effort" != "$back_effort" ]; }; then
  printf 'run-codex-review: %s/%s refused (%s); falling back to %s/%s\n' \
    "$model" "$effort" "$(jq -r '.stderr' <<<"$result" | head -1)" \
    "$back_model" "$back_effort" >&2
  back_secs=$(secs_of "$back_model" "$back_effort")
  result=$(run_seat "$back_model" "$back_effort" "$back_secs" "$out.fallback")
  write_out "$result"
  rc=0
  [ "$(jq -r '.ok' <<<"$result")" = true ] || rc=1
  [ "$(jq -r '.timedOut' <<<"$result")" = true ] && rc=124
  if [ "$rc" -eq 124 ]; then
    status "$back_model" "$back_effort" TIMEOUT "$rc"; exit 1
  fi
  if [ "$rc" -eq 0 ] && valid_output; then
    status "$back_model" "$back_effort" FALLBACK "$rc"; exit 0
  fi
  [ "$(jq -r '.quota' <<<"$result")" = true ] && codex_session_mark_off quota
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
fi

status "$model" "$effort" FAILED "$rc"; exit 1
