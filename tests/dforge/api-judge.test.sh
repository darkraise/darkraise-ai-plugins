#!/usr/bin/env bash
# run-api-judge: a ruling on the first open API budget, against stub judge CLIs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dforge"
unset CLAUDE_CONFIG_DIR DFORGE_NO_SETTINGS DFORGE_API_SPEND_FILE AR_SESSION CLAUDE_PROJECT_DIR CODEX_HOME
unset OPENAI_API_KEY ANTHROPIC_API_KEY API_JUDGE_BEAT API_JUDGE_CHAIN
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_GLOBAL XDG_CONFIG_HOME

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home" CLAUDE_CODE_SESSION_ID=s1
export DFORGE_ANTHROPIC_API_KEY=sk-test-anthropic-SENTINEL DFORGE_OPENAI_API_KEY=sk-test-openai-SENTINEL DFORGE_AGENTROUTER_API_KEY=sk-test-agentrouter-SENTINEL
WORK="$TMP/work"; STATE="$WORK/.dforge"; REPORT="$STATE/rulings-preexec-1-report.md"; JLOG="$STATE/api-judge.log"
mkdir -p "$HOME/.dforge" "$HOME/.claude/dforge/sessions/cockpit" "$WORK/docs" "$STATE" "$TMP/ws" "$TMP/mirror"
RUN="$P/scripts/run-api-judge"; SPEND="$P/scripts/api-spend"
export API_JUDGE_CLAUDE="$HERE/fixtures/stub-api-judge/claude" API_JUDGE_CODEX="$HERE/fixtures/stub-api-judge/codex"
export STUB_JUDGE_ARGS_LOG="$TMP/args.log" STUB_JUDGE_STDIN_LOG="$TMP/stdin.log" STUB_JUDGE_ENV_LOG="$TMP/env.log" STUB_JUDGE_PID_FILE="$TMP/stub.pid"

caps() { printf '{"apiBudgetAnthropic":%s,"apiBudgetOpenai":%s,"apiBudgetAgentRouter":%s}\n' "$1" "$2" "$3" > "$HOME/.dforge/config.json"; }
fresh() { rm -f "$HOME/.dforge/api-spend.json"; }
ladder() { # ladder <seconds> — the three rows of the api-judge block, with one bound
  printf '%s\n' '# fixture' '' '```api-judge' "anthropic claude-opus-5-5 medium $1" "openai gpt-6-astra xhigh $1" "agentrouter gpt-6-astra xhigh $1" '```' > "$TMP/ladder.md"
}
printf '%s\n' '{"checked":"2026-11-14","models":{"gpt-6-astra":{"source":"https://example.invalid/pricing","input":2,"cached_input":0.5,"output":8}}}' > "$TMP/prices.json"
export DFORGE_API_PRICES="$TMP/prices.json" API_JUDGE_LADDER="$TMP/ladder.md"
ladder 30

git -C "$WORK" init -q
printf '.dforge/\n' > "$WORK/.gitignore"
printf '# Spec\n' > "$WORK/docs/s.md"
git -C "$WORK" add -A
git -C "$WORK" -c user.name=t -c user.email=t@example.invalid commit -qm init
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s1"
(cd "$WORK" && bash "$P/scripts/auto-run" --session s1 start --spec docs/s.md >/dev/null 2>&1)
check "fixture: an auto run is bound to the session" "$( (cd "$WORK" && bash "$P/scripts/auto-run" status >/dev/null 2>&1); echo $?)" "0"
printf 'Rule on the lock.\n' > "$TMP/prompt.md"

run() { # run [env arguments…] — one ruling with the fixture prompt, the arguments given to env
  rm -f "$TMP/args.log" "$TMP/stdin.log" "$TMP/env.log" "$TMP/stub.pid"
  out=$(cd "$WORK" && env "$@" bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$WORK" --add-dir "$TMP/ws" --add-dir "$TMP/mirror" 2>>"$TMP/err"); rc=$?
  out=${out//$'\r'/}; printf '%s\n' "$out" >> "$TMP/all.out"
}
status_lines() { printf '%s\n' "$out" | grep ' status='; }
tried() { status_lines | sed 's/^api-judge \([a-z]*\)[: ].* status=\([A-Z]*\) .* reason=\([a-z-]*\)$/\1 \2 \3/' | tr '\n' ' '; }
started() { if [ -f "$TMP/args.log" ]; then grep -c '^budget ' "$TMP/args.log"; else echo 0; fi; }
given() { cat "$TMP/args.log" "$TMP/stdin.log" 2>/dev/null; }
report() { if [ -e "$REPORT" ]; then echo present; else echo absent; fi; }

# --- A11: the first open budget that returns a verdict writes the report ---
caps 1000 1000 1000
run
check "first open budget wins: exit 0 and one status line" "$rc $(tried)" "0 anthropic OK none "
has "A11: the status line names the budget, model, effort and report" "$out" "api-judge anthropic:claude-opus-5-5/medium status=OK exit=0 out=$REPORT "
check "A11: the report is the reply" "$(head -1 "$REPORT" | tr -d '\r')" "## Verdict"
check "A11: only the first budget's CLI ran" "$(started)" "1"
check "A11: the status line is logged" "$(grep -c ' status=OK ' "$JLOG")" "1"
has "A12: a started line is printed when the row begins" "$out" "api-judge anthropic:claude-opus-5-5/medium started"
has "the judge is given the ruling prompt" "$(given)" "Rule on the lock."
has "the judge is told to reply with the report" "$(given)" "You cannot write files. Reply with the whole report as your answer."
check "A18: each --add-dir directory reaches the Anthropic CLI" \
  "$(grep -cxF -e "$TMP/ws" -e "$TMP/mirror" "$TMP/args.log") $(grep -qxF -e '--add-dir' "$TMP/args.log" && echo flag)" "2 flag"

# --- A13: a failed budget hands on, and a verdict is required ---
: > "$JLOG"
run STUB_JUDGE_ANTHROPIC=fail
check "A13: a failed run is FAILED and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED error openai OK none "
check "A11: one status line per budget tried, logged too" "$(grep ' status=' "$JLOG" | sed 's/.* status=\([A-Z]*\) .*/\1/' | tr '\n' ' ')" "FAILED OK "
run STUB_JUDGE_ANTHROPIC=noverdict STUB_JUDGE_OPENAI=noverdict
check "A13: a reply that does not open with the verdict heading is FAILED" "$rc $(tried)" "0 anthropic FAILED no-verdict openai FAILED no-verdict agentrouter OK none "
check "A11: the budgets are tried in the block's order" "$(grep '^budget ' "$TMP/args.log" | tr '\n' ' ')" "budget anthropic budget openai budget agentrouter "

# --- the flags that confine a judge (all three ran in the run above) ---
argsof() { awk -v b="budget $1" '$0 == b { f = 1; next } f && $0 == "--" { exit } f' "$TMP/args.log"; }
after() { # after <budget> <flag> — the argument that follows <flag> on that budget's command line
  argsof "$1" | awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }'
}
check "the Anthropic judge runs bare" "$(argsof anthropic | grep -cxF -e '--bare')" "1"
check "the Anthropic judge's tools are Read, Grep and Glob only" "$(after anthropic --tools)" "Read,Grep,Glob"
check "the Anthropic judge runs on the row's model" "$(after anthropic --model)" "claude-opus-5-5"
check "the Anthropic judge runs at the row's effort" "$(after anthropic --effort)" "medium"
for b in openai agentrouter; do
  check "the $b judge's sandbox is read-only" "$(after "$b" --sandbox)$(after "$b" -s)" "read-only"
  check "the $b judge's shells do not inherit its key" "$(grep -c '^shell_environment_policy.exclude=\["DFORGE_JUDGE_KEY"\]$' "$TMP/args.log")" "2"
done
check "no judge is given wider permissions" "$(grep -c -e 'dangerously' -e 'danger-full-access' -e 'workspace-write' "$TMP/args.log")" "0"
printf 'stale\n' > "$REPORT"
run STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail STUB_JUDGE_AGENTROUTER=noverdict
check "A13: no budget produced a report: exit 3" "$rc $(tried)" "3 anthropic FAILED error openai FAILED error agentrouter FAILED no-verdict "
check "A13: no report file is left, a stale one included" "$(report)" "absent"

# --- A12, A13: progress lines and the bounds ---
fresh
run API_JUDGE_BEAT=1 STUB_JUDGE_ANTHROPIC=slow STUB_JUDGE_SLOW=3
check "A12: a running line is printed while the row runs" "$([ "$(printf '%s\n' "$out" | grep -c '^api-judge anthropic running [0-9]*s$')" -ge 1 ] && echo yes || echo no)" "yes"
check "a slow run inside its bound still rules" "$rc" "0"
ladder 2
before=$(date +%s)
run STUB_JUDGE_ANTHROPIC=hang
check "A13: a run past its seconds is TIMEOUT and ends the chain" "$rc $(tried)" "3 anthropic TIMEOUT timeout "
has "A13: the timeout line" "$out" "api-judge anthropic:claude-opus-5-5/medium status=TIMEOUT exit=124 out=- "
check "A13: no further budget is tried after a timeout" "$(started)" "1"
check "A13: the timed-out CLI is stopped" "$(kill -0 "$(cat "$TMP/stub.pid")" 2>/dev/null && echo running || echo stopped)" "stopped"
check "A13: the row's seconds bound the wait" "$([ $(( $(date +%s) - before )) -lt 20 ] && echo yes || echo no)" "yes"
ladder 30
before=$(date +%s)
run API_JUDGE_CHAIN=6 STUB_JUDGE_ANTHROPIC=hang
check "A13: the chain's seconds bound a row that has more of its own" "$rc $(tried)$([ $(( $(date +%s) - before )) -lt 20 ] && echo bounded)" "3 anthropic TIMEOUT timeout bounded"
before=$(date +%s)
run API_JUDGE_CHAIN=10 STUB_JUDGE_ANTHROPIC=slow-fail STUB_JUDGE_SLOW=3 STUB_JUDGE_OPENAI=hang
check "A13: a later row gets only what is left of the chain" "$rc $(tried)$([ $(( $(date +%s) - before )) -lt 25 ] && echo bounded)" "3 anthropic FAILED error openai TIMEOUT timeout bounded"

# --- A14: a closed budget starts no CLI ---
fresh; caps 0 0 0
run
check "A14: cap 0 skips every budget" "$rc $(tried)$(started)" "3 anthropic SKIPPED off openai SKIPPED off agentrouter SKIPPED off 0"
has "A14: a skipped line" "$out" "api-judge anthropic:claude-opus-5-5/medium status=SKIPPED exit=0 out=- spent=0.0000 reason=off"
caps 1000 1000 1000
run -u DFORGE_ANTHROPIC_API_KEY ANTHROPIC_API_KEY=vendor-anthropic
check "A14: no key skips the budget, whatever the vendor's variable holds" "$rc $(tried)" "0 anthropic SKIPPED no-key openai OK none "
run -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_OPENAI_API_KEY -u DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic
check "A10: with only the vendors' variables set no CLI starts" "$rc $(tried)$(started)" "3 anthropic SKIPPED no-key openai SKIPPED no-key agentrouter SKIPPED no-key 0"
fresh; caps 10 1000 1000; bash "$SPEND" add anthropic 9.6
run
check "A14: spend at 95% of the cap skips the budget" "$rc $(tried)" "0 anthropic SKIPPED spent openai OK none "
fresh; caps 1000 1000 1000
printf '%s\n' '{"checked":"2026-11-14","models":{}}' > "$TMP/noprices.json"
run DFORGE_API_PRICES="$TMP/noprices.json" STUB_JUDGE_ANTHROPIC=fail
check "A14: no price row skips openai and agentrouter, never anthropic" "$rc $(tried)" "3 anthropic FAILED error openai SKIPPED no-price agentrouter SKIPPED no-price "

# --- a CLI that is not there, and a ladder with no api-judge block ---
fresh
run API_JUDGE_CLAUDE="$TMP/no-such-claude"
check "a CLI that cannot start is FAILED no-cli and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED no-cli openai OK none "
check "a CLI that cannot start is charged nothing" "$(bash "$SPEND" status | tr -d '\r' | sed -n 's/^api-budget anthropic .* spent=\([0-9.]*\) .*/\1/p')" "0.0000"
printf '# no block\n' > "$TMP/noblock.md"
run API_JUDGE_LADDER="$TMP/noblock.md"
check "a ladder with no api-judge block: one line, exit 3, no CLI" "$rc|$out|$(started)" "3|api-judge none status=SKIPPED exit=3 out=- spent=0.0000 reason=no-roster|0"

run API_JUDGE_CHAIN=0
check "a chain with no time left: one SKIPPED chain line per row, exit 3, no CLI" "$rc $(tried)$(started)" "3 anthropic SKIPPED chain openai SKIPPED chain agentrouter SKIPPED chain 0"

# --- A17: auto runs only ---
run CLAUDE_CODE_SESSION_ID=other
check "A17: no run bound: one line, exit 3, no CLI" "$rc|$out|$(started)" "3|api-judge none status=SKIPPED exit=3 out=- spent=0.0000 reason=no-run|0"

# --- --dry-run and usage ---
rm -f "$TMP/args.log"
dry=$(cd "$WORK" && bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$WORK" --dry-run 2>>"$TMP/err" | tr -d '\r'); printf '%s\n' "$dry" >> "$TMP/all.out"
check "--dry-run names each open budget's command and starts nothing" "$(printf '%s\n' "$dry" | grep -c '^api-judge [a-z]*:[^ ]* dry-run: ') $(started)" "3 0"
has "--dry-run shows a key as its variable's name" "$dry" '$DFORGE_ANTHROPIC_API_KEY'
has "--dry-run: the Anthropic line runs bare" "$(printf '%s\n' "$dry" | grep '^api-judge anthropic:')" "--bare"
has "--dry-run: the Anthropic line carries the tool limit" "$(printf '%s\n' "$dry" | grep '^api-judge anthropic:')" "Read,Grep,Glob"
check "--dry-run: both Codex lines carry the read-only sandbox" "$(printf '%s\n' "$dry" | grep -c 'read-only')" "2"
(cd "$WORK" && bash "$RUN" --report "$REPORT" --cwd "$WORK" 2>/dev/null); check "a missing --prompt: exit 2" "$?" "2"
(cd "$WORK" && bash "$RUN" --prompt "$TMP/none.md" --report "$REPORT" --cwd "$WORK" 2>/dev/null); check "a prompt file that does not exist: exit 2" "$?" "2"
(cd "$WORK" && bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$TMP/nowhere" 2>/dev/null); check "a --cwd that is not a directory: exit 2" "$?" "2"
(cd "$WORK" && bash "$RUN" --prompt "$TMP/prompt.md" --cwd "$WORK" 2>/dev/null); check "a missing --report: exit 2" "$?" "2"

# --- A9: what a judge child is given ---
sha() { printf '%s' "$1" | sha256sum | cut -c1-16; }
envof() { awk -v b="budget $1" '$0 == b { f = 1; next } f && $0 == "--" { exit } f' "$TMP/env.log"; }
holds() { # holds <budget> <value…> — how many of the child's variables hold one of the values
  local budget=$1 n=0 value; shift
  for value in "$@"; do n=$(( n + $(envof "$budget" | grep -c " $(sha "$value")\$") )); done
  echo "$n"
}
ALL_KEYS=(sk-test-anthropic-SENTINEL sk-test-openai-SENTINEL sk-test-agentrouter-SENTINEL vendor-openai vendor-anthropic)
fresh; caps 1000 1000 1000; ladder 30
run OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic CODEX_HOME="$TMP/user-codex" STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail \
  ANTHROPIC_AUTH_TOKEN=vendor-token ANTHROPIC_BASE_URL=https://gateway.invalid CLAUDE_CODE_OAUTH_TOKEN=vendor-oauth \
  CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_VERTEX=1 CLAUDE_CODE_USE_FOUNDRY=1 ANTHROPIC_BEDROCK_BASE_URL=https://gateway.invalid \
  ANTHROPIC_VERTEX_BASE_URL=https://gateway.invalid OPENAI_BASE_URL=https://gateway.invalid
check "fixture: all three children ran" "$(started)" "3"
lacks "A8: no key value is on a judge's command line" "$(cat "$TMP/args.log")" "SENTINEL"
check "A9: the Anthropic child holds no DFORGE key variable" "$(envof anthropic | grep -c '^DFORGE_[A-Z]*_API_KEY ')" "0"
check "A9: the Anthropic child's ANTHROPIC_API_KEY is the DFORGE key, not the vendor variable's value" "$(envof anthropic | grep '^ANTHROPIC_API_KEY ')" "ANTHROPIC_API_KEY $(sha sk-test-anthropic-SENTINEL)"
check "A9: the Anthropic child holds one key, its own" "$(holds anthropic "${ALL_KEYS[@]}")" "1"
for b in anthropic openai agentrouter; do
  check "A9: the $b child holds no variable that routes its key or prompt elsewhere" \
    "$(envof "$b" | grep -c -E '^(ANTHROPIC_AUTH_TOKEN|ANTHROPIC_BASE_URL|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX|CLAUDE_CODE_USE_FOUNDRY|ANTHROPIC_BEDROCK_BASE_URL|ANTHROPIC_VERTEX_BASE_URL|OPENAI_BASE_URL) ')" "0"
done
for b in openai agentrouter; do
  check "A9: the $b child holds no DFORGE key variable" "$(envof "$b" | grep -c '^DFORGE_[A-Z]*_API_KEY ')" "0"
  check "A9: the $b child holds no Anthropic key variable" "$(envof "$b" | grep -c '^ANTHROPIC_API_KEY ')" "0"
  check "A9: the $b child holds one key, its own" "$(holds "$b" "${ALL_KEYS[@]}") $(holds "$b" "sk-test-$b-SENTINEL")" "1 1"
  home=$(envof "$b" | sed -n 's/^CODEX_HOME //p')
  check "A9: the $b child's CODEX_HOME is not the user's" "$(case "$home" in unset | "$TMP/user-codex" | "$HOME/.codex") echo shared ;; *) echo own ;; esac)" "own"
done

# --- A8: a reply holding a key value is discarded ---
fresh
run STUB_JUDGE_ANTHROPIC=leak STUB_JUDGE_LEAK=sk-test-openai-SENTINEL
check "A8: a reply holding a key is FAILED key-in-reply and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED key-in-reply openai OK none "
lacks "A8: the report holds no key" "$(cat "$REPORT")" "SENTINEL"
run STUB_JUDGE_ANTHROPIC=leak STUB_JUDGE_LEAK=sk-test-agentrouter-SENTINEL STUB_JUDGE_OPENAI=fail STUB_JUDGE_AGENTROUTER=fail
check "A8: a reply holding a key is never written to the report" "$rc $(report)" "3 absent"

# --- A15: the worktree must not change during a run ---
fresh
for mode in write commit; do
  run "STUB_JUDGE_ANTHROPIC=$mode"
  check "A15: a run during which a $mode happened is FAILED wrote and ends the chain" "$rc $(tried)$(started)" "3 anthropic FAILED wrote 1"
  check "A15: after a $mode the reply is not written" "$(report)" "absent"
  rm -f "$WORK/stray.txt"
done
run STUB_JUDGE_ANTHROPIC=write-ignored
check "A15: a change git ignores is not a write" "$rc $(tried)" "0 anthropic OK none "

# --- A16: what a run cost is charged to its budget ---
spent() { bash "$SPEND" status | tr -d '\r' | sed -n "s/^api-budget $1 .* spent=\([0-9.]*\) .*/\1/p"; }
fresh; run
check "A16: the Anthropic run is charged the cost its CLI reports" "$(spent anthropic) $(status_lines | sed 's/.* spent=\([0-9.]*\) .*/\1/')" "0.2500 0.2500"
fresh; run STUB_JUDGE_ANTHROPIC=fail
check "A16: a run that reported nothing is charged 1.00, a Codex run is priced from its tokens" "$(spent anthropic) $(spent openai)" "1.0000 2.5000"
fresh; run STUB_JUDGE_ANTHROPIC=noverdict STUB_JUDGE_OPENAI=noverdict
check "A16: a failed run is charged what it reported, agentrouter from the same table" "$(spent anthropic) $(spent openai) $(spent agentrouter)" "0.2500 2.5000 2.5000"
fresh; ladder 2
run STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=hang-usage
check "A16: a timed-out run is charged its last token total" "$(tried)$(spent openai)" "anthropic FAILED error openai TIMEOUT timeout 2.5000"
stopped() { kill -0 "$(cat "$TMP/stub.pid")" 2>/dev/null && echo running || echo stopped; }
check "A13: a timed-out Codex CLI that had reported usage is stopped" "$(stopped)" "stopped"
fresh
run STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=hang
check "A16: a timed-out run that reported nothing is charged 1.00" "$(spent openai)" "1.0000"
check "A13: a timed-out Codex CLI is stopped" "$(stopped)" "stopped"
ladder 30
fresh; run STUB_JUDGE_ANTHROPIC=silent
check "A16: a verdict with no cost reported is still charged 1.00" "$rc $(spent anthropic)" "0 1.0000"
fresh; caps 0 0 0; run
check "A16: a skipped budget is charged nothing" "$(spent anthropic)" "0.0000"
caps 1000 1000 1000

# --- a charge that cannot be recorded does not undo a ruling ---
fresh
LOCKBASE=$( . "$P/scripts/lib/lock.sh"; dr_lock_base "$HOME/.dforge/api-spend.json" )
mkdir "$LOCKBASE.lockd"; uname -n > "$LOCKBASE.lockd/host"; printf '%s\n' "$$" > "$LOCKBASE.lockd/pid"
: > "$TMP/err"
run DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=3
rm -rf "$LOCKBASE.lockd"
check "a charge that fails leaves the ruling and its status line standing" "$rc $(tried)$(report)" "0 anthropic OK none present"
has "a charge that fails is reported on stderr" "$(cat "$TMP/err")" "run-api-judge: the charge to anthropic was not recorded"
check "a charge that fails is logged" "$(grep -c '^api-judge anthropic charge-failed spent=0.2500$' "$JLOG")" "1"
check "a charge that fails records nothing" "$(spent anthropic)" "0.0000"

# --- A8: no key value anywhere ---
lacks "A8: no key value in stdout, stderr, the log, the spend file or the state directory" \
  "$(cat "$TMP/all.out" "$TMP/err" "$JLOG" "$HOME/.dforge/api-spend.json" 2>/dev/null; grep -rh SENTINEL "$STATE" 2>/dev/null)" "SENTINEL"

# --- a project whose first auto run created .dforge/, which nothing ignores yet ---
W2="$TMP/work2"; mkdir -p "$W2/docs"; printf '# Spec\n' > "$W2/docs/s.md"
git -C "$W2" init -q && git -C "$W2" add -A && git -C "$W2" -c user.name=t -c user.email=t@example.invalid commit -qm init
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s2"
(cd "$W2" && bash "$P/scripts/auto-run" --session s2 start --spec docs/s.md >/dev/null 2>&1)
fresh; caps 5 0 0
out=$(cd "$W2" && AR_SESSION=s2 bash "$RUN" --prompt "$TMP/prompt.md" --report "$W2/.dforge/r.md" --cwd "$W2" 2>>"$TMP/err" | tr -d '\r'); rc=$?
check "an unignored state directory: the judge's own log line is not a write" "$rc $(tried)" "0 anthropic OK none "
check "an unignored state directory: it now ignores itself" "$(cat "$W2/.dforge/.gitignore" 2>/dev/null | tr -d '\r')" "*"

# --- a pre-run snapshot that cannot be taken: HEAD made unborn after the run is bound ---
W3="$TMP/work3"; mkdir -p "$W3/docs"; printf '# Spec\n' > "$W3/docs/s.md"; printf '.dforge/\n' > "$W3/.gitignore"
git -C "$W3" init -q && git -C "$W3" add -A && git -C "$W3" -c user.name=t -c user.email=t@example.invalid commit -qm init
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s3"
(cd "$W3" && bash "$P/scripts/auto-run" --session s3 start --spec docs/s.md >/dev/null 2>&1)
git -C "$W3" update-ref -d "$(git -C "$W3" symbolic-ref HEAD)"
fresh; caps 5 0 0; rm -f "$TMP/args.log"
out=$(cd "$W3" && AR_SESSION=s3 bash "$RUN" --prompt "$TMP/prompt.md" --report "$W3/.dforge/r.md" --cwd "$W3" 2>>"$TMP/err" | tr -d '\r'); rc=$?
check "no snapshot: one FAILED line, exit 3, no CLI, no report" "$rc $(tried) $(started) $([ -e "$W3/.dforge/r.md" ] && echo present || echo absent)" "3 anthropic FAILED snapshot  0 absent"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
