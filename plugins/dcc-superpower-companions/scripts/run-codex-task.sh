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
    --dry-run) dry=1; shift; continue ;;
    --brief|--report|--model|--effort|--cwd|--timeout|--resume) ;;
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
  esac
  shift 2
done

[ -n "$brief" ]  || die "--brief is required"
[ -n "$report" ] || die "--report is required"
[ -n "$model" ]  || die "--model is required"
[ -n "$effort" ] || die "--effort is required"
[ -n "$cwd" ]    || die "--cwd is required"
[ -f "$brief" ]  || die "brief not found: $brief"
[ -d "$cwd" ]    || die "cwd not found: $cwd"
[ -f "$SCHEMA" ] || die "schema not found: $SCHEMA"

# Resolved once: reset pathspecs are repo-relative while these files are written
# caller-relative, and `git reset` on a non-matching path exits 0, so the miss
# would be silent.
case "$report" in /*|[A-Za-z]:*) ;; *) report="$(pwd)/$report" ;; esac

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

# `git add -A` stages the whole repository no matter which subdirectory it runs
# from, so a cwd below the root would sweep unrelated uncommitted work into this
# task's commit. --show-prefix is empty only at the root, and unlike comparing
# --show-toplevel against pwd it does not care that git and MSYS disagree over
# whether a path starts with D:/ or /d/.
prefix=$(git -C "$cwd" rev-parse --show-prefix) || die "not a git repository: $cwd"
[ -z "$prefix" ] || die "cwd must be the repository root, but sits under $prefix"
base=$(git -C "$cwd" rev-parse HEAD) || die "cannot resolve HEAD in $cwd"

codex_pid=""
codex_winpid=""
# Two mechanisms for two topologies. `codex` on PATH is a POSIX shim that
# execs node, which then spawns codex's real payload - a native codex-*.exe -
# via a raw CreateProcess outside the MSYS runtime entirely; that binary holds
# no MSYS pgid, so only `taskkill //T`, which walks native ParentProcessId,
# can reach it. `kill -TERM -<pgid>` is the complementary case: it reaches
# whatever MSYS-aware descendants share the `set -m` group below, which is
# what a real Windows ParentProcessId lookup was shown live NOT to find (a
# backgrounded MSYS child survived `taskkill //F //T` on its own parent's
# winpid while confirmed still running). Both run every time, since neither
# topology can be assumed absent.
kill_codex_tree() {
  kill -0 "$codex_pid" 2>/dev/null || return 0
  [ -n "$codex_winpid" ] && taskkill //F //T //PID "$codex_winpid" >/dev/null 2>&1
  kill -TERM -"$codex_pid" 2>/dev/null || true
  sleep 1
  kill -0 "$codex_pid" 2>/dev/null && kill -KILL -"$codex_pid" 2>/dev/null
  return 0
}
cleanup() {
  [ -n "$codex_pid" ] && kill_codex_tree
  return 0
}
trap cleanup EXIT INT TERM HUP

# Codex can exit 0 without writing its final message. Left in place, a previous
# run's verdict would be read as this one's - guaranteed on every resume round,
# which reuses the same report path - and the wrapper would commit under a stale
# subject it never earned. rm -f succeeds on a missing file but can fail on a
# locked one, so the clear is verified rather than assumed.
rm -f "$last" "$jsonl"
[ ! -f "$last" ] || die "could not clear stale verdict file: $last"

# A non-interactive script has job control off, so a plain `cmd &` inherits
# this script's own process group instead of getting a fresh one - confirmed
# live: `kill -TERM -"$codex_pid"` then fails with "No such process" because
# no group with that id exists. `set -m` around just this launch is what makes
# the backgrounded job (and anything it execs) its own group, which is what
# `kill_codex_tree` signals; `setsid` would do the same but isn't on this box.
set -m
codex "${argv[@]}" < "$prompt" > "$jsonl" 2> "$report.stderr" &
codex_pid=$!
set +m
# Captured once, right after launch, while codex_pid (node) is still alive:
# this is node's own Windows process, which is what taskkill //T needs to
# start its native tree-walk from.
codex_winpid=$(cat "/proc/$codex_pid/winpid" 2>/dev/null || true)

# Polled rather than wrapped in `timeout`: the kill has to happen while the
# child is still live. `timeout` reaps its child before wait returns, leaving
# nothing left to signal by the time a kill would fire - and it would also put
# a wrapper process between us and node, which is exactly what breaks
# taskkill's native tree-walk (see codex_winpid above).
timed_out=no
waited=0
while [ "$waited" -lt "$timeout_s" ] && kill -0 "$codex_pid" 2>/dev/null; do
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
if kill -0 "$codex_pid" 2>/dev/null; then
  rc=124
else
  wait "$codex_pid"; rc=$?
fi
[ "$timed_out" = yes ] && rc=124
codex_pid=""
codex_winpid=""

# Event field naming has varied across Codex releases, so match on any of the
# shapes rather than pinning one that a later version may rename.
thread_id=$(jq -r 'select(type=="object")
  | (.thread_id // .threadId // .session_id // .sessionId // empty)' \
  "$jsonl" 2>/dev/null | head -1)
[ -n "$thread_id" ] || thread_id="${thread:-unknown}"

status=BLOCKED
summary=""
subject=""
if [ -f "$last" ]; then
  status=$(jq -r '.status // "BLOCKED"' "$last" 2>/dev/null || echo BLOCKED)
  summary=$(jq -r '.summary // ""' "$last" 2>/dev/null || true)
  subject=$(jq -r '.commit_subject // ""' "$last" 2>/dev/null || true)
fi
[ "$rc" -eq 0 ] || status=BLOCKED

committed=no
if [ "$status" = DONE ] && [ -n "$subject" ]; then
  git -C "$cwd" add -A -- . || die "git add failed in $cwd"
  # Keep the wrapper's own scratch out of the task's commit. A no-op when the
  # report lives in a git-ignored directory, load-bearing when it does not.
  for artefact in "$prompt" "$jsonl" "$last" "$report.stderr" "$report"; do
    git -C "$cwd" reset -q -- "$artefact" 2>/dev/null || true
  done
  if git -C "$cwd" diff --cached --quiet; then
    # A task can legitimately finish with nothing to commit. Dying here would
    # leave the controller no report and no status line to read.
    committed=empty
  else
    git -C "$cwd" commit -q -m "$subject" || die "commit failed in $cwd"
    committed=yes
  fi
fi

head=$(git -C "$cwd" rev-parse HEAD)

{
  printf '# Task report\n\n'
  printf -- '- executor: codex %s / %s\n' "$model" "$effort"
  printf -- '- thread: %s\n' "$thread_id"
  printf -- '- status: %s\n' "$status"
  printf -- '- commits: %s..%s\n' "${base:0:7}" "${head:0:7}"
  [ "$committed" = empty ] && printf -- '- note: DONE with an empty diff; nothing was committed\n'
  printf '\n## Summary\n\n%s\n' "$summary"
  if [ "$status" = NEEDS_CONTEXT ]; then
    printf '\n## Questions\n\n'
    jq -r '.questions[]? | "- " + .' "$last" 2>/dev/null || true
  fi
  if [ "$status" != DONE ]; then
    printf '\n## Working tree\n\nLeft uncommitted on purpose. Last 20 stderr lines:\n\n```\n'
    tail -20 "$report.stderr" 2>/dev/null || true
    printf '```\n'
  fi
} > "$report"

printf 'codex %s/%s status=%s commits=%s..%s thread=%s report=%s\n' \
  "$model" "$effort" "$status" "${base:0:7}" "${head:0:7}" "$thread_id" "$report"

[ "$status" = DONE ]
