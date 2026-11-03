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

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GATE_STUB_LINE:-agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=cache}"\n' > "$fixture/gate-stub"
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
check "rejects a rung with no agy-timeout row" "$(dry_rc --model gemini-3.8-flash --effort low)" "2"
check "names the missing agy-timeout row" "$(grep -c 'no agy-timeout row for gemini-3.8-flash/low' "$fixture/err")" "1"
check "rejects claude-opus-5-5, which no agy block names" "$(dry_rc --model claude-opus-5-5 --effort high)" "2"
check "the refusal names both blocks" \
  "$(grep -c 'model is not an agy-assignment or agy-successor rung: claude-opus-5-5' "$fixture/err")" "1"
check "admits Argon low from agy-assignment" \
  "$(dry --model gemini-4-argon --effort low | sed -n '2p' | jq -r '.timeoutSeconds')" "900"
check "admits Argon high from agy-assignment" \
  "$(dry --model gemini-4-argon --effort high | sed -n '2p' | jq -r '.timeoutSeconds')" "1500"
check "admits a Claude rung named only in agy-successor" "$(dry_rc --model claude-sonnet-5-5 --effort high)" "0"
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

# --- the Claude fallback runs only while the gate says fallback=on (A8) -------
FB_OFF='agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=2099-01-01T00:00:00Z source=cache'
n=$(calls)
newwork fallback-off
GATE_STUB_LINE="$FB_OFF" run
check "a Claude model is refused while the fallback is off" "$?" "2"
check "the refusal names the reset time" \
  "$(grep -c 'the agy Claude fallback is off until 2099-01-01T00:00:00Z (quota)' "$fixture/err")" "1"
newwork fallback-session
GATE_STUB_LINE='agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=- source=cache' run
check "a fallback mark with no reset refuses a Claude model" "$?" "2"
check "that refusal says the end of the session" \
  "$(grep -c 'the agy Claude fallback is off until the end of the session (quota)' "$fixture/err")" "1"
newwork fallback-absent
GATE_STUB_LINE='agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache' run
check "a gate line without the fallback field refuses a Claude model" "$?" "2"
check "the refused Claude runs never launch agy" "$(calls)" "$n"
newwork fallback-gemini
GATE_STUB_LINE="$FB_OFF" run --model gemini-3.8-flash --effort medium
check "a Gemini model still runs while the fallback is off" "$?" "0"
check "the Gemini run launched agy" "$(calls)" "$((n + 1))"

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
run --model gemini-4-argon --effort high --resume conv-1
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

newwork needs
STUB_AGY_MODE=needs-context run
check "a NEEDS_CONTEXT verdict is not DONE" "$?" "1"
check "a NEEDS_CONTEXT verdict reports its status" "$(status_line | grep -c 'status=NEEDS_CONTEXT exit=0 ')" "1"
check "a NEEDS_CONTEXT report lists the questions" \
  "$(grep -A2 '^## Questions$' "$R" | tail -1 | tr -d '\r')" "- Which file holds the setting?"
check "a NEEDS_CONTEXT verdict leaves pending work" "$(jq -r .phase "$(state_of "$W")")" "pending"
check "a NEEDS_CONTEXT verdict commits nothing" "$(git -C "$W" log --format=%s | wc -l | tr -d ' ')" "1"

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
# --- a failed run says why, in the keys the controller reads ------------------
case "$(uname -s)" in MINGW*|MSYS*) windows=yes ;; *) windows=no ;; esac
skip() { printf 'skip - %s\n' "$1"; }

newwork classify
errcase() { # errcase <label> <mode> <error text> <reason> <exit>
  STUB_AGY_MODE="$2" STUB_AGY_ERROR="$3" run
  check "$1: the run is not DONE" "$?" "1"
  check "$1: the status line is BLOCKED with exit $5" \
    "$(status_line | sed -n 's/.* status=\([A-Z_]*\) exit=\([0-9]*\) .*/\1 \2/p')" "BLOCKED $5"
  check "$1: the report names reason $4" "$(grep -c "^reason=$4\$" "$R")" "1"
}
errcase "a plain error" error "something failed" error 1
check "a plain error carries the raw error text" "$(grep -c '^something failed$' "$R")" "1"
check "a plain error is not a timeout" "$(grep -c '^timedOut=true$' "$R")" "0"
check "a plain error has no timeout note" "$(status_line | grep -c 'note=')" "0"
check "a plain error leaves pending work" "$(jq -r .phase "$(state_of "$W")")" "pending"
errcase "an unrecognised failure with no text" no-schema "" error 0
errcase "an unknown model" error "unknown model gemini-9-flash" unknown-model 1
errcase "a withdrawn model" error "Model foo-1 not found" unknown-model 1
errcase "a quota error" error "Quota exceeded for this account" quota 1
errcase "a 429" error "HTTP 429 Too Many Requests" quota 1
errcase "a rate limit in any case" error "Rate-Limit reached" quota 1
errcase "a resource exhaustion" error "RESOURCE_EXHAUSTED: try later" quota 1
errcase "429 inside a sha" error "cannot read object 3f429ab" error 1
errcase "429 inside a line number" error "parse failed at line 1429" error 1
STUB_AGY_TEXT="Error: quota exhausted for this account" errcase "a plain-text quota" text "" quota 1
check "a plain-text failure is shown in the report" "$(grep -c '^Error: quota exhausted for this account$' "$R")" "1"
check "a plain-text failure is kept beside the report" \
  "$(tr -d '\r' < "$(jq -r .artifacts.report "$(state_of "$W")").stdout" 2>/dev/null)" "Error: quota exhausted for this account"
STUB_AGY_TEXT="Something unexpected happened" errcase "a plain-text error" text "" error 1
check "a plain-text error is shown in the report" "$(grep -c '^Something unexpected happened$' "$R")" "1"
mkdir -p "$fixture/stderrshim"
cat > "$fixture/stderrshim/agy" <<'SHIM'
#!/usr/bin/env bash
printf 'HTTP 429 Too Many Requests\n' >&2
printf '{"conversation_id":"","status":"ERROR","response":""}\n'
exit 1
SHIM
chmod +x "$fixture/stderrshim/agy"
PATH="$fixture/stderrshim:$PATH" run
check "a failure with no error field is classified from stderr" "$(grep -c '^reason=quota$' "$R")" "1"
errcase "a print timeout" print-timeout "" timeout 124
check "a print timeout reports timedOut" "$(grep -c '^timedOut=true$' "$R")" "1"
check "a print timeout is flagged on the status line" "$(status_line | grep -c ' note=timed-out')" "1"
check "a print timeout is never DONE" "$(status_line | grep -c 'status=DONE')" "0"
check "a stopped print timeout leaves pending work" "$(jq -r .phase "$(state_of "$W")")" "pending"

# --- a clean run is confirmed stopped, a hung one is bounded ------------------
newwork clean
run
check "a clean run carries no note" "$(status_line | grep -c 'note=')" "0"
newwork padded
run --timeout 08
check "a zero-padded timeout runs" "$?" "0"
check "a zero-padded timeout is read in base 10" "$(arg_after --print-timeout)" "8s"

sleepers() { ps -eo pid=,args= 2>/dev/null | awk '$2 == "sleep" && $3 == "300" { print $1 }' | sort; }
newwork outer
before="$(sleepers)"
AGY_TASK_GRACE=1 STUB_AGY_MODE=hang run --timeout 1
check "an outer timeout is not DONE" "$?" "1"
check "an outer timeout reports exit 124" "$(status_line | grep -c 'status=BLOCKED exit=124 ')" "1"
check "an outer timeout is flagged timed-out" "$(status_line | grep -c ' note=timed-out')" "1"
check "an outer timeout reports reason timeout" "$(grep -c '^reason=timeout$' "$R")" "1"
check "an outer timeout reports timedOut" "$(grep -c '^timedOut=true$' "$R")" "1"
check "an outer timeout names its bound in the report" "$(grep -c '^- note: timed out after 1s$' "$R")" "1"
if [ "$windows" = no ]; then
  leaked="$(comm -13 <(printf '%s\n' "$before") <(sleepers))"
  check "an outer timeout leaves no process in the group" "$leaked" ""
  [ -z "$leaked" ] || kill -KILL $leaked 2>/dev/null
  check "a confirmed stop leaves pending work" "$(jq -r .phase "$(state_of "$W")")" "pending"
  check "a confirmed stop carries no unconfirmed note" "$(status_line | grep -c 'writer-unconfirmed')" "0"
else
  check "on Windows an outer kill is never confirmed" "$(status_line | grep -c ' note=writer-unconfirmed')" "1"
fi

# A process that ignores TERM outlives the run: nothing proves the writer stopped.
if [ "$windows" = no ]; then
  mkdir -p "$fixture/stubborn"
  cat > "$fixture/stubborn/agy" <<SHIM
#!/usr/bin/env bash
( trap '' TERM; exec sleep 25 ) &
printf '%s\n' "\$!" > "$fixture/stubborn.pid"
exec "$STUBDIR/agy" "\$@"
SHIM
  chmod +x "$fixture/stubborn/agy"
  newwork survivor
  PATH="$fixture/stubborn:$PATH" run
  check "a surviving process is not DONE" "$?" "1"
  check "a surviving process is flagged unconfirmed" "$(status_line | grep -c ' note=writer-unconfirmed')" "1"
  check "a surviving process is not reported as a timeout" "$(status_line | grep -c 'note=timed-out')" "0"
  check "a surviving process blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
  check "a surviving process commits nothing" "$(git -C "$W" log --format=%s | grep -c 'feat(stub)')" "0"
  check "the report says the stop was not confirmed" \
    "$(grep -c '^- note: agy run not confirmed stopped; the task is blocked until it is$' "$R")" "1"
  run
  check "a blocked unconfirmed task cannot relaunch" "$?" "2"
  kill -KILL "$(cat "$fixture/stubborn.pid")" 2>/dev/null || true
else
  skip "a TERM-proof survivor needs POSIX process groups"
fi

# An interrupt stops the group it started and blocks the task.
if [ "$windows" = no ]; then
  newwork interrupted
  before="$(sleepers)"
  n=$(calls)
  STUB_AGY_MODE=hang bash "$SCRIPT" --cwd "$W" --task-id task-one --write-set "$fixture/scope.json" \
    --brief "$fixture/brief.md" --report "$R" --model claude-sonnet-5-5 --effort medium --timeout 120 \
    > "$fixture/out" 2> "$fixture/err" &
  wrapper=$!
  for _ in $(seq 1 50); do [ "$(calls)" -gt "$n" ] && break; sleep 0.2; done
  kill -TERM "$wrapper"
  wait "$wrapper"
  check "an interrupted run exits 143" "$?" "143"
  check "an interrupted run blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
  leaked="$(comm -13 <(printf '%s\n' "$before") <(sleepers))"
  check "an interrupted run leaves no process in the group" "$leaked" ""
  [ -z "$leaked" ] || kill -KILL $leaked 2>/dev/null
else
  skip "an interrupt test needs POSIX signals"
fi

# --- agy may not move refs or the index (A7) ----------------------------------
guard_case() { # guard_case <name> <mode> <file agy writes> <ref the report names>
  newwork "$1"
  STUB_AGY_MODE="$2" STUB_AGY_WRITE="$3" run
  check "$1: the run is not DONE" "$?" "1"
  check "$1: the status line is BLOCKED exit 1" "$(status_line | grep -c 'status=BLOCKED exit=1 ')" "1"
  check "$1: the report names the moved ref" "$(grep -c "agy changed git refs: $4" "$R")" "1"
  check "$1: the task is blocked" "$(jq -r .phase "$(state_of "$W")")" "blocked"
  check "$1: nothing is committed under the reported subject" "$(git -C "$W" log --format=%s HEAD | grep -c 'feat(stub): add out')" "0"
}
guard_case guard-commit git-commit base.txt refs/heads/guard-commit
guard_case guard-stash git-stash base.txt refs/stash

# Other worktrees, fetches and sessions move shared refs while a task runs (a
# parallel wave's sibling commits on its own branch), so those are reported
# rather than blocked; a deleted ref, a tag or a rewritten branch still blocks.
git -C "$fixture/primary" worktree add -qb sibling "$fixture/sibling"
git -C "$fixture/primary" branch keep
git -C "$fixture/primary" update-ref refs/heads/rewind \
  "$(git -C "$fixture/primary" commit-tree 'HEAD^{tree}' -p HEAD -m next)"
outside_case() { # outside_case <name> <git command run during agy's turn> <ref the note names | ->
  newwork "$1"
  STUB_AGY_MODE=git-run STUB_AGY_GIT="$2" run
  check "$1: the run is DONE" "$?" "0"
  check "$1: the task completes" "$(jq -r .phase "$(state_of "$W")")" "complete"
  check "$1: the work is committed" "$(git -C "$W" log -1 --format=%s | tr -d '\r')" "feat(stub): add out"
  if [ "$3" = - ]; then
    check "$1: the report has no outside-refs note" "$(grep -c 'refs outside this worktree' "$R")" "0"
  else
    check "$1: the report names the outside ref" \
      "$(grep -cE "^- note: refs outside this worktree changed during the run:.* $3( |\$)" "$R")" "1"
  fi
}
outside_case outside-sibling "git -C '$fixture/sibling' commit -q --allow-empty -m sibling" refs/heads/sibling
outside_case outside-branch "git branch stub-branch" refs/heads/stub-branch
outside_case outside-stash "printf 'x\n' > '$fixture/sibling/base.txt' && git -C '$fixture/sibling' stash -q" refs/stash
outside_case outside-remote "git update-ref refs/remotes/origin/main HEAD" -

block_case() { # block_case <name> <git command run during agy's turn> <ref the report names>
  newwork "$1"
  STUB_AGY_MODE=git-run STUB_AGY_GIT="$2" run
  check "$1: the run is not DONE" "$?" "1"
  check "$1: the report names the ref" "$(grep -c "agy changed git refs: $3;" "$R")" "1"
  check "$1: the task is blocked" "$(jq -r .phase "$(state_of "$W")")" "blocked"
}
block_case block-delete "git branch -D keep" refs/heads/keep
block_case block-rewind "git update-ref refs/heads/rewind HEAD" refs/heads/rewind
block_case block-tag "git tag stub-tag" refs/tags/stub-tag
block_case block-stash-drop "git stash drop -q" refs/stash

mkdir -p "$fixture/indexshim"
cat > "$fixture/indexshim/agy" <<SHIM
#!/usr/bin/env bash
"$STUBDIR/agy" "\$@"
rc=\$?
git add -- out.txt
exit \$rc
SHIM
chmod +x "$fixture/indexshim/agy"
newwork guard-index
PATH="$fixture/indexshim:$PATH" run
check "an index change is not DONE" "$?" "1"
check "an index change is named in the report" "$(grep -c 'agy changed the git index' "$R")" "1"
check "an index change blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
check "an index change commits nothing" "$(git -C "$W" log --format=%s | grep -c 'feat(stub)')" "0"
check "an index change leaves the staged file in place" "$(git -C "$W" diff --cached --name-only | tr -d '\r')" "out.txt"

# --- a quota closes the lane for the rest of the session (A8) ------------------
session_file="$DR_AGY_SESSION_DIR/run-agy-task-test.json"
session_state() { jq -r '[.usable, .lane, .reason] | map(tostring) | join("/")' "$session_file" 2>/dev/null | tr -d '\r'; }
rm -rf "$DR_AGY_SESSION_DIR"
newwork session-plain
STUB_AGY_MODE=error STUB_AGY_ERROR="something failed" run
check "a plain error leaves the session file absent" "$([ -e "$session_file" ] && echo yes || echo no)" "no"
newwork session-model
STUB_AGY_MODE=error STUB_AGY_ERROR="unknown model gemini-9-flash" run
check "an unknown model leaves the session file absent" "$([ -e "$session_file" ] && echo yes || echo no)" "no"
sfield() { jq -r "$1 | tostring" "$session_file" 2>/dev/null | tr -d '\r'; }
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
in_window() { # in_window <epoch> <before> <after> <seconds>
  if [ "$1" -ge $(( $2 + $4 )) ] 2>/dev/null && [ "$1" -le $(( $3 + $4 )) ]; then echo yes; else echo no; fi; }
seed_open() { rm -rf "$DR_AGY_SESSION_DIR"; mkdir -p "$DR_AGY_SESSION_DIR"
  printf '{"session_id":"run-agy-task-test","usable":true,"review":false,"lane":true,"reason":"ok","resets_at":null,"resets_at_epoch":null}\n' > "$session_file"; }
quota_lines() { grep -A"$1" '^reason=quota$' "$R" | tr -d '\r' | tr '\n' ' '; }
QUOTA_RESET='RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h2m3s.'
QUOTA_BARE='Quota exceeded for this account'

# A Gemini quota closes the lane until the reset the error names (A6, A14).
seed_open; newwork lane-reset
before=$(date -u +%s)
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run --model gemini-3.8-flash --effort medium
after=$(date -u +%s)
epoch=$(sfield .resets_at_epoch)
check "a Gemini quota closes the lane" "$(session_state)" "false/false/quota"
check "a Gemini quota's reset is 3723 s after agy exits" "$(in_window "$epoch" "$before" "$after" 3723)" "yes"
check "a Gemini quota's reset is written in ISO 8601 UTC" "$(sfield .resets_at)" "$(iso "$epoch")"
check "a Gemini quota writes no fallback mark" "$(sfield 'has("fallback")')" "false"
check "the report says the lane was marked until the reset" "$(quota_lines 2)" "reason=quota marked=lane until=$(iso "$epoch") "

# Without a reset the lane stays closed for the session (A10).
seed_open; newwork lane-bare
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_BARE" run --model gemini-3.8-flash --effort medium
check "a Gemini quota with no reset closes the lane for the session" \
  "$(session_state)/$(sfield .resets_at_epoch)" "false/false/quota/null"
check "the report says the lane was marked" "$(quota_lines 1)" "reason=quota marked=lane "
check "a quota with no reset prints no until line" "$(grep -c '^until=' "$R")" "0"

# A Claude quota closes only the fallback (A7, A10, A14).
seed_open; newwork fallback-reset
before=$(date -u +%s)
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run
after=$(date -u +%s)
epoch=$(sfield .fallback.resets_at_epoch)
check "a Claude quota leaves the lane open" "$(session_state)" "true/true/ok"
check "a Claude quota marks the fallback off" "$(sfield .fallback.usable)/$(sfield .fallback.reason)" "false/quota"
check "a Claude quota's reset is 3723 s after agy exits" "$(in_window "$epoch" "$before" "$after" 3723)" "yes"
check "a Claude quota's reset is written in ISO 8601 UTC" "$(sfield .fallback.resets_at)" "$(iso "$epoch")"
check "the report says the fallback was marked until the reset" "$(quota_lines 2)" "reason=quota marked=fallback until=$(iso "$epoch") "
seed_open; newwork fallback-bare
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_BARE" run
check "a Claude quota with no reset marks the fallback for the session" \
  "$(session_state)/$(sfield .fallback.usable)/$(sfield .fallback.resets_at_epoch)" "true/true/ok/false/null"
check "the report says the fallback was marked" "$(quota_lines 1)" "reason=quota marked=fallback "

rm -rf "$DR_AGY_SESSION_DIR"
newwork session-text
STUB_AGY_MODE=text STUB_AGY_TEXT="RESOURCE_EXHAUSTED: try later" run --model gemini-3.8-flash --effort medium
check "a plain-text quota turns agy off for the session" "$(session_state)" "false/false/quota"
# stderr can carry output of the commands the model ran, so a quota word there
# labels the run but marks nothing (A11).
rm -rf "$DR_AGY_SESSION_DIR"
newwork session-stderr
PATH="$fixture/stderrshim:$PATH" run --model gemini-3.8-flash --effort medium
check "a quota seen only on stderr is still reported as quota" "$(grep -c '^reason=quota$' "$R")" "1"
check "a quota seen only on stderr reports marked=none" "$(quota_lines 1)" "reason=quota marked=none "
check "a quota seen only on stderr leaves the session file absent" "$([ -e "$session_file" ] && echo yes || echo no)" "no"

# The same quota through the real gate: it keeps the answer past --refresh. Node
# cannot run a bash-script stub on Windows, and the gate's probe spawns agy.
SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$STUBDIR/agy" 2>/dev/null | tr -d '\r')
if [ "$SPAWNABLE" = yes ]; then
  saved_gate="$AGY_TASK_GATE"
  unset AGY_TASK_GATE
  rm -rf "$DR_AGY_SESSION_DIR"
  gate_fields() { bash "$P/scripts/agy-gate" "$@" 2>/dev/null | tail -1 | tr -d '\r' \
    | sed -n 's/.* usable=\([a-z]*\) reason=\([^ ]*\) .* lane=\([a-z]*\) .*/\1 \2 \3/p'; }
  check "the real gate opens the lane on a trusted, signed-in stub" "$(gate_fields)" "true ok true"
  newwork quota
  STUB_AGY_MODE=error STUB_AGY_ERROR="quota exceeded" run --model gemini-3.8-flash --effort medium
  check "a quota run through the real gate is not DONE" "$?" "1"
  check "the gate reports quota after the run" "$(gate_fields)" "false quota false"
  check "the gate keeps quota through --refresh" "$(gate_fields --refresh)" "false quota false"
  n=$(calls)
  run --task-id task-two --model gemini-3.8-flash --effort medium
  check "the next wrapper call is refused" "$?" "2"
  check "the next wrapper call names quota" "$(grep -c 'agy lane is off for this session (quota)' "$fixture/err")" "1"
  check "the next wrapper call never runs agy" "$(calls)" "$n"
  gate_line() { bash "$P/scripts/agy-gate" "$@" 2>/dev/null | tail -1 | tr -d '\r'; }
  # A reset time ends the lane mark: once it has passed, the gate probes again (A6).
  rm -rf "$DR_AGY_SESSION_DIR"; gate_line >/dev/null
  newwork quota-reset
  STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run --model gemini-3.8-flash --effort medium
  epoch=$(sfield .resets_at_epoch)
  check "the gate prints the lane's reset time" "$(gate_line)" \
    "agy-gate usable=false reason=quota review=false lane=false resets_at=$(iso "$epoch") fallback=on fallback_resets_at=- source=cache"
  jq '.resets_at_epoch = 1000' "$session_file" > "$session_file.tmp" && mv -f "$session_file.tmp" "$session_file"
  check "a passed reset reopens the lane through a fresh probe" "$(gate_line)" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=probe"

  # A Claude quota closes only the fallback (A7, A10).
  newwork fallback-gate
  STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run
  epoch=$(sfield .fallback.resets_at_epoch)
  check "after a Claude quota the gate keeps the lane and turns the fallback off" "$(gate_line)" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=$(iso "$epoch") source=cache"
  n=$(calls)
  newwork fallback-gate-gemini
  run --model gemini-3.8-flash --effort medium
  check "a Gemini run still launches agy while the fallback is off" "$(calls)" "$((n + 1))"
  newwork fallback-gate-claude
  run
  check "a Claude run is refused while the fallback is off" "$?" "2"
  check "the refused Claude run never launches agy" "$(calls)" "$((n + 1))"
  rm -rf "$DR_AGY_SESSION_DIR"; gate_line >/dev/null
  newwork fallback-gate-bare
  STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_BARE" run
  check "a Claude quota with no reset keeps the fallback off through --refresh" "$(gate_line --refresh)" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=- source=probe"
  export AGY_TASK_GATE="$saved_gate"
else
  skip "the real-gate quota chain needs a probe that can run the stub"
fi
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
