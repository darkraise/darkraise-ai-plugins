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
while [ $# -gt 0 ]; do
  case "$1" in
    --brief)   brief="${2:-}";     shift 2 ;;
    --report)  report="${2:-}";    shift 2 ;;
    --model)   model="${2:-}";     shift 2 ;;
    --effort)  effort="${2:-}";    shift 2 ;;
    --cwd)     cwd="${2:-}";       shift 2 ;;
    --timeout) timeout_s="${2:-}"; shift 2 ;;
    --resume)  thread="${2:-}";    shift 2 ;;
    --dry-run) dry=1;              shift   ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$brief" ]  || die "--brief is required"
[ -n "$report" ] || die "--report is required"
[ -n "$model" ]  || die "--model is required"
[ -n "$effort" ] || die "--effort is required"
[ -n "$cwd" ]    || die "--cwd is required"
[ -f "$brief" ]  || die "brief not found: $brief"
[ -d "$cwd" ]    || die "cwd not found: $cwd"
[ -f "$SCHEMA" ] || die "schema not found: $SCHEMA"

block codex-assignment | awk '{print $2}' | sort -u | grep -qxF -- "$model" \
  || die "model is not a rung in codex-assignment: $model"
case " $VALID_EFFORTS " in
  *" $effort "*) ;;
  *) die "invalid reasoning effort: $effort (valid: $VALID_EFFORTS)" ;;
esac

if [ -z "$timeout_s" ]; then
  timeout_s=$(block codex-timeout | awk -v k="$model/$effort" '$1 == k {print $2}')
  [ -n "$timeout_s" ] || die "no codex-timeout row for $model/$effort"
fi

# Every per-invocation flag is rebuilt here, including on resume: a bare
# `codex exec resume <id>` inherits the user's config defaults instead.
argv=(exec)
[ -n "$thread" ] && argv+=(resume "$thread")
argv+=(
  -C "$cwd"
  -s workspace-write
  -m "$model"
  -c "model_reasoning_effort=$effort"
  --json
  --output-schema "$SCHEMA"
  -o "$report.last.json"
)

if [ "$dry" -eq 1 ]; then
  printf 'timeout %s codex' "$timeout_s"
  printf ' %s' "${argv[@]}"
  printf '\n'
  exit 0
fi

die "execution is not implemented yet"
