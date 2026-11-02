#!/usr/bin/env bash
# The agy wrapper reaches a paid model through a pointer prompt, so these cases
# assert what the stub agy was handed and what the wrapper left behind. No case
# starts a real agy.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
SCRIPT="$P/scripts/run-agy-task.sh"
STUBDIR="$HERE/fixtures/stub-agy"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# Every path the suite writes lives under $fixture, and the real session files,
# policy and Antigravity login stay out of reach.
export HOME="$fixture/home" DR_AGY_SESSION_DIR="$fixture/sessions" DR_AGY_POLICY="$fixture/policy.json" \
  CLAUDE_CODE_SESSION_ID=run-agy-task-test CLAUDE_PROJECT_DIR=
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME"
printf '{"cli":"agy","min_version":"1.4.12","max_major":1,"calibrated":"1.4.12","trust":{"smoke":"pass"}}\n' > "$DR_AGY_POLICY"
export STUB_AGY_ARGS_LOG="$fixture/args.log"
export PATH="$STUBDIR:$PATH"
check "agy resolves to the stub" "$([ "$(command -v agy)" -ef "$STUBDIR/agy" ] && echo yes || echo no)" "yes"

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GATE_STUB_LINE:-agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache}"\n' > "$fixture/gate-stub"
export AGY_TASK_GATE="$fixture/gate-stub"

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
calls() { if [ -f "$STUB_AGY_ARGS_LOG" ]; then grep -c '^-p$' "$STUB_AGY_ARGS_LOG" || true; else echo 0; fi; }
last_call() { awk '$0 == "--" { last = cur; cur = ""; next } { cur = cur $0 "\n" } END { printf "%s", last }' "$STUB_AGY_ARGS_LOG"; }
arg_after() { last_call | tr -d '\r' | awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }'; }
has_arg() { last_call | tr -d '\r' | grep -qxF -- "$1" && echo yes || echo no; }

git init -q "$fixture/primary"
git -C "$fixture/primary" config user.email fixture@example.com
git -C "$fixture/primary" config user.name Fixture
git -C "$fixture/primary" config core.autocrlf false
printf 'base\n' > "$fixture/primary/base.txt"
printf 'claude conventions\n' > "$fixture/primary/CLAUDE.md"
printf 'agents conventions\n' > "$fixture/primary/AGENTS.md"
git -C "$fixture/primary" add base.txt CLAUDE.md AGENTS.md
git -C "$fixture/primary" commit -qm 'test: seed fixture'
printf 'Implement only the approved files.\n' > "$fixture/brief.md"
printf '["base.txt","out.txt","second.txt","new file.txt"]\n' > "$fixture/scope.json"

newwork() { # newwork <name>; sets W (worktree) and R (human report)
  W="$fixture/$1"; R="$fixture/$1.report.md"
  git -C "$fixture/primary" worktree add -qb "$1" "$W"
}
run() { bash "$SCRIPT" --cwd "$W" --task-id task-one --write-set "$fixture/scope.json" \
  --brief "$fixture/brief.md" --report "$R" --model claude-sonnet-5-5 --effort medium "$@" > "$fixture/out" 2> "$fixture/err"; }
dry() { bash "$SCRIPT" --brief "$fixture/brief.md" --report "$fixture/dry.md" --cwd "$fixture/primary" --dry-run "$@" 2>"$fixture/err"; }
dry_rc() { dry "$@" >/dev/null; echo $?; }
state_of() { # state_of <worktree>
  printf '%s/dforge/tasks/%s/state.json' "$(git -C "$1" rev-parse --absolute-git-dir)" "$(printf task-one | git -C "$1" hash-object --stdin)"
}
status_line() { tail -1 "$fixture/out" | tr -d '\r'; }

# --- the files the wrapper reads ----------------------------------------------
check "the wrapper exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"
check "the report schema is byte-identical to the codex schema" \
  "$(cmp -s "$P/scripts/agy-report-schema.json" "$P/scripts/codex-report-schema.json" && echo yes || echo no)" "yes"
for word in add commit stash reset checkout switch rebase branch tag update-ref worktree; do
  check "the contract forbids git $word" \
    "$(grep -qF "git $word" "$P/scripts/agy-task-contract.md" && echo yes || echo no)" "yes"
done
for field in status summary commit_subject questions discovered_issues assumptions; do
  check "the contract names the $field field" \
    "$(grep -qF "\`$field\`" "$P/scripts/agy-task-contract.md" && echo yes || echo no)" "yes"
done

# --- validation happens before anything is spawned ----------------------------
check "rejects a model absent from agy-assignment" "$(dry_rc --model gpt-4o --effort medium)" "2"
check "rejects a codex model" "$(dry_rc --model gpt-6.1-sol --effort medium)" "2"
check "rejects xhigh, which only codex accepts" "$(dry_rc --model claude-sonnet-5-5 --effort xhigh)" "2"
check "rejects a multi-word effort" "$(dry_rc --model claude-sonnet-5-5 --effort 'medium high')" "2"
check "rejects a rung with no agy-timeout row" "$(dry_rc --model claude-opus-5-5 --effort low)" "2"
check "rejects a non-numeric timeout" "$(dry_rc --model claude-sonnet-5-5 --effort medium --timeout 30m)" "2"
check "rejects an unknown flag" "$(dry_rc --model claude-sonnet-5-5 --effort medium --bogus x)" "2"
check "rejects a missing brief" \
  "$(bash "$SCRIPT" --brief "$fixture/nope.md" --report "$fixture/r.md" --cwd "$fixture/primary" --model claude-sonnet-5-5 --effort medium --dry-run >/dev/null 2>&1; echo $?)" "2"
check "a trailing flag with no value exits 2 rather than hanging" \
  "$(timeout 10 bash "$SCRIPT" --brief "$fixture/brief.md" --report "$fixture/r.md" --cwd "$fixture/primary" --model claude-sonnet-5-5 --effort medium --resume >/dev/null 2>&1; echo $?)" "2"
check "accepts a valid rung" "$(dry_rc --model claude-sonnet-5-5 --effort medium)" "0"
check "validation reaches agy never" "$(calls)" "0"
req=$(dry --model claude-sonnet-5-5 --effort medium | sed -n '2p')
check "dry run: the timeout comes from agy-timeout" "$(jq -r '.timeoutSeconds' <<<"$req")" "1200"
check "dry run: an explicit timeout wins" \
  "$(dry --model claude-sonnet-5-5 --effort high --timeout 42 | sed -n '2p' | jq -r '.timeoutSeconds')" "42"
check "dry run: a resume names its conversation" \
  "$(dry --model claude-sonnet-5-5 --effort medium --resume conv-9 | sed -n '2p' | jq -r '.conversation')" "conv-9"
check "dry run: a fresh run names no conversation" "$(jq -r '.conversation' <<<"$req")" "null"

# --- a closed lane never reaches agy -------------------------------------------
newwork closed
GATE_STUB_LINE='agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache' run
check "a closed lane is refused" "$?" "2"
check "a closed lane names the gate reason" "$(grep -c 'agy lane is off for this session (quota)' "$fixture/err")" "1"
check "a closed lane never launches agy" "$(calls)" "0"

# --- a DONE run commits the approved write set (A6) ----------------------------
newwork happy
base="$(git -C "$W" rev-parse HEAD)"
run
check "a DONE run exits 0" "$?" "0"
head="$(git -C "$W" rev-parse HEAD)"
line="$(status_line)"
check "the status line names rung, status, exit, commits and thread" \
  "${line%% report=*}" "agy claude-sonnet-5-5/medium status=DONE exit=0 commits=${base:0:7}..${head:0:7} thread=conv-1"
check "the status line names a report that exists" "$([ -f "${line##*report=}" ] && echo yes || echo no)" "yes"
check "the commit holds the produced file" "$(git -C "$W" show HEAD:out.txt 2>/dev/null)" "stub"
check "the commit holds nothing else" "$(git -C "$W" show --name-only --format= HEAD | tr -d '\r')" "out.txt"
check "the commit carries the reported subject" "$(git -C "$W" log -1 --format=%s)" "feat(stub): add out"
check "the report names the rung" "$(grep -c '^- executor: agy claude-sonnet-5-5 / medium$' "$R")" "1"
check "the report carries the summary" "$(grep -A2 '^## Summary$' "$R" | tail -1 | tr -d '\r')" "stub summary"
check "the report says None for empty assumptions" "$(grep -A2 '^## Assumptions made$' "$R" | tail -1 | tr -d '\r')" "None"
state="$(state_of "$W")"
check "the record is complete" "$(jq -r .phase "$state")" "complete"
check "the record keeps the conversation" "$(jq -r .thread "$state")" "conv-1"
check "the record points the prompt artifact at the prompt directory" \
  "$(jq -r .artifacts.prompt "$state" | grep -c '/prompt/attempt-1\.md$')" "1"

# --- the prompt reaches agy as a pointer only (A10) ---------------------------
taskdir="$(cd "$(dirname "$state")" && pwd -P)"
promptfile="$taskdir/prompt/attempt-1.md"
check "the prompt file holds the brief" "$(head -1 "$promptfile" | tr -d '\r')" "Implement only the approved files."
check "the prompt file inlines CLAUDE.md under its heading" \
  "$(grep -A2 '^## Repository conventions (CLAUDE.md)$' "$promptfile" | tail -1 | tr -d '\r')" "claude conventions"
check "the prompt file inlines AGENTS.md under its heading" \
  "$(grep -A2 '^## Repository conventions (AGENTS.md)$' "$promptfile" | tail -1 | tr -d '\r')" "agents conventions"
check "the prompt file ends with the task contract" "$(grep -c '^## How to complete this task$' "$promptfile")" "1"
# Paths are compared by identity, not by spelling: on Windows an 8.3 TEMP makes
# the wrapper's native form and this suite's differ while naming one file.
posix() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }
same() { [ "$(posix "$1")" -ef "$2" ] && echo same || echo "differs: $1"; }
pointer="$(arg_after -p)"
pointed="${pointer#Your complete instructions are in }"; pointed="${pointed%. Read the whole file first and follow it.}"
check "the -p argument is the pointer sentence" \
  "$(printf '%s' "$pointer" | sed -E 's/^Your complete instructions are in .+\. Read the whole file first and follow it\.$/pointer/')" "pointer"
check "the pointer names the prompt file" "$(same "$pointed" "$promptfile")" "same"
check "--add-dir names the prompt directory" "$(same "$(arg_after --add-dir)" "$taskdir/prompt")" "same"
check "the prompt directory holds no task record" "$([ -e "$taskdir/prompt/state.json" ] && echo yes || echo no)" "no"
check "the task record sits beside the prompt directory" "$([ -f "$taskdir/state.json" ] && echo yes || echo no)" "yes"
check "agy gets the report schema" "$(same "$(arg_after --json-schema)" "$P/scripts/agy-report-schema.json")" "same"
check "agy gets the model" "$(arg_after --model)" "claude-sonnet-5-5"
check "agy gets the effort" "$(arg_after --effort)" "medium"
check "agy gets the print timeout from agy-timeout" "$(arg_after --print-timeout)" "1200s"
check "agy asks for JSON output" "$(arg_after --output-format)" "json"
check "agy runs unattended" "$(has_arg --dangerously-skip-permissions)" "yes"
check "a fresh run passes no conversation" "$(has_arg --conversation)" "no"

newwork big
marker=BRIEFMARKER9
{ for _ in $(seq 1 2500); do printf '%s %s\n' "$marker" "a line of brief text that makes the file large padding padding padding"; done; } > "$fixture/big-brief.md"
run --brief "$fixture/big-brief.md"
check "a 200 KB brief still runs" "$?" "0"
check "a large brief still passes the same sentence" "$(arg_after -p | grep -c '^Your complete instructions are in .*\. Read the whole file first and follow it\.$')" "1"
check "no argument carries the brief" "$(grep -c "$marker" "$STUB_AGY_ARGS_LOG" || true)" "0"
bigtask="$(cd "$(dirname "$(state_of "$W")")" && pwd -P)"
check "the brief lands in the prompt file" "$(grep -c "$marker" "$bigtask/prompt/attempt-1.md")" "2500"

# --- a resume pins thread, model and effort (A9) -------------------------------
newwork resume
run
check "resume fixture: first run succeeds" "$?" "0"
STUB_AGY_WRITE=second.txt run --resume conv-1
check "a matching resume succeeds" "$?" "0"
check "a resume passes the thread as --conversation" "$(arg_after --conversation)" "conv-1"
check "a resume repeats the model" "$(arg_after --model)" "claude-sonnet-5-5"
check "a resume repeats the effort" "$(arg_after --effort)" "medium"
check "the resume commit holds its own file" "$(git -C "$W" show HEAD:second.txt 2>/dev/null)" "stub"
check "the second attempt writes a second prompt file" \
  "$([ -f "$(cd "$(dirname "$(state_of "$W")")" && pwd -P)/prompt/attempt-2.md" ] && echo yes || echo no)" "yes"
n=$(calls)
run --resume other-thread
check "a resume with another thread is refused" "$?" "2"
run --effort high --resume conv-1
check "a resume with another effort is refused" "$?" "2"
run --model claude-opus-5-5 --effort high --resume conv-1
check "a resume with another model is refused" "$?" "2"
check "a refused resume never reaches agy" "$(calls)" "$n"

# --- an incomplete run leaves pending work, and recovery hands it back ---------
newwork pending
STUB_AGY_MODE=blocked run
check "a BLOCKED verdict is not DONE" "$?" "1"
check "a BLOCKED verdict reports the status" "$(status_line | grep -c 'status=BLOCKED exit=0 ')" "1"
check "a BLOCKED verdict persists pending state" "$(jq -r .phase "$(state_of "$W")")" "pending"
check "a BLOCKED verdict commits nothing" "$(git -C "$W" log --format=%s | wc -l | tr -d ' ')" "1"
check "a BLOCKED report carries an agy error section" "$(grep -c '^## Agy error$' "$R")" "1"
STUB_AGY_MODE=no-schema run
check "a run with no structured output is not DONE" "$?" "1"
check "a run with no structured output reports BLOCKED" "$(status_line | grep -c 'status=BLOCKED ')" "1"
check "a failure with no error text says so" "$(grep -c '^agy returned no error text$' "$R")" "1"
bash "$SCRIPT" --cwd "$W" --task-id task-one --handback > "$fixture/out" 2> "$fixture/err"
check "handback transfers the stopped pending task" "$?" "0"
run
check "a handed-back task cannot resume" "$?" "2"
printf 'claude finished\n' > "$W/out.txt"
git -C "$W" add out.txt
git -C "$W" commit -qm 'feat(test): finish handed-back task'
bash "$SCRIPT" --cwd "$W" --task-id task-one --release > "$fixture/out" 2> "$fixture/err"
check "a finished handed-back task releases ownership" "$?" "0"
run --task-id task-two
check "a released worktree accepts a new task" "$?" "0"

# --- a failed commit is recovered without agy ---------------------------------
newwork recover
printf '#!/usr/bin/env bash\nexit 1\n' > "$fixture/primary/.git/hooks/pre-commit"
chmod +x "$fixture/primary/.git/hooks/pre-commit"
run
check "a commit hook failure exits two" "$?" "2"
check "a commit hook failure blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
rm -f "$fixture/primary/.git/hooks/pre-commit"
n=$(calls)
bash "$SCRIPT" --cwd "$W" --task-id task-one --recover-commit > "$fixture/out" 2> "$fixture/err"
check "commit recovery succeeds" "$?" "0"
check "commit recovery never launches agy" "$(calls)" "$n"
check "the recovered commit holds the produced file" "$(git -C "$W" show HEAD:out.txt 2>/dev/null)" "stub"

# --- output outside the write set is never committed ---------------------------
newwork outside
STUB_AGY_MODE=outside-write STUB_AGY_OUTSIDE="$W/rogue.txt" run
check "an out-of-scope file blocks committing" "$?" "2"
check "an out-of-scope file is preserved" "$(cat "$W/rogue.txt" 2>/dev/null)" "stub"
check "an out-of-scope file is not committed" "$(git -C "$W" ls-tree --name-only HEAD rogue.txt)" ""
check "an out-of-scope file blocks the task record" "$(jq -r .phase "$(state_of "$W")")" "blocked"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
