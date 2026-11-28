#!/usr/bin/env bash
# Acceptance checks for docs/dforge/specs/2026-11-27-review-3c81c7d6-fixes-design.md:
# A7 (the stop hooks hold a bounded number of times), A8 (a TERM to the Codex
# runner's group leaves no process), A9's migrate half (a plan rewrite killed
# partway) and A15 (bash 3.2). The cockpit guard (A6), the darkmem reconcile
# half of A9 and the portability lint (A10) are in their own files. Each check
# name starts with the statement it answers.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
P="$ROOT/plugins/dforge"
S="$P/scripts"
TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export LC_ALL=C DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR \
  DFORGE_SESSION_ID XDG_STATE_HOME NODE_TEST_CONTEXT
PIDS_TO_KILL=""
NAME15="dforge-a15-$$"
cleanup() {
  local p
  for p in $PIDS_TO_KILL; do kill -KILL -- "$p" 2>/dev/null; done
  command -v docker >/dev/null 2>&1 && docker rm -f "$NAME15" >/dev/null 2>&1
  cd / && rm -rf "$TMP"
}
trap cleanup EXIT

. "$HERE/fixtures/cockpit-ack.sh"
cockpit_ack_start "$HOME"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
skip() { printf 'skip - %s\n' "$1"; }
alive() { # alive PID — running, and not a zombie waiting to be reaped
  local s
  s=$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')
  [ -n "$s" ] && [ "${s#Z}" = "$s" ]
}

case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) IS_WINDOWS=1 ;; *) IS_WINDOWS=0 ;; esac

# =====================================================================
# A7: turn-end.sh, an auto run whose stop fails past the hold cap
# =====================================================================
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-7"
(cd "$REPO" && bash "$S/auto-run" --session s-7 start --spec docs/s.md --register docs/r.md >/dev/null)
AUTO="$REPO/.dforge/sdd/auto-run.json"
jq '.pending = "compact"' "$AUTO" > "$AUTO.tmp" && mv "$AUTO.tmp" "$AUTO"

stop() { # stop <session> <last message> <stop_hook_active true|false>
  jq -n --arg sid "$1" --arg cwd "$REPO" --arg msg "$2" --argjson active "$3" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:$active,last_assistant_message:$msg}' |
    bash "$S/turn-end.sh"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }

# Every locked write fails, so `auto-run stop` cannot stop the run.
out=$(DFORGE_FLOCK=false stop s-7 'Done.' false)
first=$(decision "$out")
CAP=$(jq -r '.systemMessage // ""' <<<"$out" | sed -n 's/.*hold 1 of \([0-9][0-9]*\).*/\1/p')
check "A7: the first stop of an auto run's turn without its sentinel is held, and the hold names a cap" "$first|${CAP:+named}" "block|named"
CAP=${CAP:-3}
decisions=$first
for _ in $(seq 1 $((CAP + 4))); do
  decisions="$decisions $(decision "$(DFORGE_FLOCK=false stop s-7 'Done.' true)")"
done
# A stop that goes through ends the turn; stops after it are another turn's.
blocks=$(tr ' ' '\n' <<<"$decisions" | awk '$0 == "none" { exit } $0 == "block" { n++ } END { print n + 0 }')
# The hold past the cap, which says the run could not be stopped, is the one
# hold a failed stop adds to the cap's own.
check "A7: when auto-run stop fails past the cap, no more than cap+1 stops are held" "$([ "$blocks" -le $((CAP + 1)) ] && echo ok || echo "too many: $blocks of [$decisions]")" "ok"
passed_at=$(tr ' ' '\n' <<<"$decisions" | grep -n '^none$' | head -1 | cut -d: -f1)
check "A7: when auto-run stop fails past the cap, the next stop after the cap's holds goes through (within cap+2 stops)" \
  "$([ -n "$passed_at" ] && [ "$passed_at" -le $((CAP + 2)) ] && echo ok || echo "no pass in [$decisions]")" "ok"
check "A7: the auto run was in fact still active (the stop did fail)" "$(jq -r .active "$AUTO")" "true"

# =====================================================================
# A7: impl-stop-gate, a counter that cannot be written
# =====================================================================
GATE="$S/impl-stop-gate"
MISSING="Report: $TMP/no-such-report.md"
gate_repo() { # gate_repo NAME — a fresh repository; prints its path
  git init -q -b main "$TMP/$1" && printf '%s' "$TMP/$1"
}
gate_run() { # gate_run REPO AGENT — one stop of AGENT with a report that does not exist; prints the exit code
  local input
  input=$(jq -nc --arg c "$1" --arg i "$2" --arg m "QA done.
$MISSING" '{session_id:"s-g",cwd:$c,hook_event_name:"SubagentStop",stop_hook_active:false,agent_id:$i,agent_type:"dforge:impl-sonnet-high",last_assistant_message:$m}')
  bash "$GATE" <<<"$input" >/dev/null 2>&1
  printf '%s' "$?"
}
gate_codes() { # gate_codes REPO AGENT N — the exit codes of N stops in a row, space separated
  local i codes=""
  for i in $(seq 1 "$3"); do codes="$codes $(gate_run "$1" "$2")"; done
  printf '%s' "${codes# }"
}
count_of() { tr ' ' '\n' <<<"$1" | grep -c "^$2\$"; }

GR1=$(gate_repo gate-writable)
codes=$(gate_codes "$GR1" a-ctl 1)
check "A7: control: a gate whose counter is writable blocks a missing report" "$codes" "2"

GR2=$(gate_repo gate-counter-dir)
GS2=$(cd "$GR2" && bash "$S/dforge-path" state | tr -d '\r')
mkdir -p "$GS2/impl-stop-gate/a-dir"
codes=$(gate_codes "$GR2" a-dir 8)
check "A7: a counter that cannot be written (it is a directory): the first stop goes through" "${codes%% *}" "0"
check "A7: a counter that cannot be written (it is a directory): no stop in 8 is blocked more times than the cap of 2" \
  "$([ "$(count_of "$codes" 2)" -le 2 ] && echo ok || echo "[$codes]")" "ok"

GR3=$(gate_repo gate-state-file)
GS3=$(cd "$GR3" && bash "$S/dforge-path" state | tr -d '\r')
mkdir -p "$GS3"
printf 'not a directory\n' > "$GS3/impl-stop-gate"
codes=$(gate_codes "$GR3" a-file 8)
check "A7: a counter directory that cannot be made: the first stop goes through" "${codes%% *}" "0"
check "A7: a counter directory that cannot be made: no stop in 8 is blocked more times than the cap of 2" \
  "$([ "$(count_of "$codes" 2)" -le 2 ] && echo ok || echo "[$codes]")" "ok"

# =====================================================================
# A8: a TERM to the Codex runner's process group
# =====================================================================
if [ "$IS_WINDOWS" = 1 ] || ! command -v setsid >/dev/null 2>&1 || ! command -v ps >/dev/null 2>&1; then
  skip "A8: needs setsid and ps"
else
  STUB="$TMP/stub-plugin"
  cp -R "$HERE/fixtures/stub-codex-plugin" "$STUB"
  # The hung turn also starts a child of its own, in the client's group.
  CODEX_JS="$STUB/scripts/lib/codex.mjs"
  sed -i.bak 's|^  if (m === "hang") {$|  if (m === "hang") {\n    if (process.env.STUB_CHILD_FILE) fs.writeFileSync(process.env.STUB_CHILD_FILE, String((await import("node:child_process")).spawn("sleep", ["300"], { stdio: "ignore" }).pid));|' "$CODEX_JS"
  CFG="$TMP/cfg"
  mkdir -p "$CFG/plugins" "$TMP/work8"
  printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$CFG/settings.json"
  jq -nc --arg p "$STUB" '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' > "$CFG/plugins/installed_plugins.json"
  jq -nc '{plugin:"codex@openai-codex", min_version:"1.0.3", max_major:1, trust:{calibration:"pending", smoke:"pending"}}' > "$TMP/policy.json"
  fence='```'
  { printf '%scodex-judge\n' "$fence"; printf 'gpt-6-astra high 120\ngpt-6.1-sol high 120\n'; printf '%s\n' "$fence"; } > "$TMP/ladder.md"
  printf '#!/usr/bin/env bash\nprintf "codex-gate usable=true reason=ok review=true resets_at=- source=cache\\n"\n' > "$TMP/gate-stub"
  git -C "$TMP/work8" init -q -b main && git -C "$TMP/work8" commit -q --allow-empty -m base
  printf 'review this\n' > "$TMP/prompt8.txt"
  : > "$TMP/stub.pid"; : > "$TMP/stub.child"
  DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=a8 CODEX_REVIEW_GATE="$TMP/gate-stub" CODEX_REVIEW_LADDER="$TMP/ladder.md" \
    CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR= DR_CODEX_POLICY="$TMP/policy.json" STUB_MODE=hang STUB_PID_FILE="$TMP/stub.pid" \
    STUB_CHILD_FILE="$TMP/stub.child" STUB_CALL_FILE="$TMP/stub.calls" STUB_EVENT_LOG="$TMP/stub.events" \
    setsid bash "$S/run-codex-review.sh" --kind task --cwd "$TMP/work8" --out "$TMP/o8.json" --prompt "$TMP/prompt8.txt" >/dev/null 2>&1 &
  rpid=$!
  PIDS_TO_KILL="$PIDS_TO_KILL -$rpid"
  for _ in $(seq 1 100); do [ -s "$TMP/stub.pid" ] && [ -s "$TMP/stub.child" ] && break; sleep 0.1; done
  # Every process the runner started: those in its process group, and the
  # descendants of any of them.
  started=" $rpid"
  for _ in 1 2 3 4; do
    tree=$(ps -eo pid=,ppid=,pgid= | awk -v root="$rpid" -v known="$started" '
      { pid[NR] = $1; ppid[NR] = $2; pgid[NR] = $3 }
      END {
        n = split(known, k, " "); for (i = 1; i <= n; i++) have[k[i]] = 1
        for (i = 1; i <= NR; i++) if (pgid[i] == root || ppid[i] in have) have[pid[i]] = 1
        for (p in have) printf "%s ", p
      }')
    started=" $tree"
  done
  nstart=$(wc -w <<<"$started" | tr -d ' ')
  check "A8: the runner started more than one process (it is running before the TERM)" "$([ "$nstart" -ge 3 ] && echo ok || echo "$started")" "ok"
  kill -TERM -- "-$rpid" 2>/dev/null
  sleep 10
  left=""
  for p in $started; do alive "$p" && left="$left $p"; done
  check "A8: after a TERM to the runner's process group, none of its processes is alive 10 s later" "${left:-none}" "none"
  for p in $left; do kill -KILL "$p" 2>/dev/null; done
  wait "$rpid" 2>/dev/null
fi

# =====================================================================
# A9: dforge-migrate, a plan rewrite killed partway
# =====================================================================
if [ "$IS_WINDOWS" = 1 ] || ! command -v setsid >/dev/null 2>&1; then
  skip "A9: needs setsid"
else
  REAL_AWK=$(command -v awk) REAL_MV=$(command -v mv)
  PLAN_LINES=1500
  make_legacy() { # make_legacy DIR — a repository with one active plan under docs/forge, naming dr-forge: skills
    git init -q -b main "$1"
    git -C "$1" commit -q --allow-empty -m init
    mkdir -p "$1/docs/forge/plans"
    {
      printf '# Active plan\n\n'
      for i in $(seq 1 "$PLAN_LINES"); do printf 'line %s: run dr-forge:executing-plans, then dr-superpowers:verification-before-completion\n' "$i"; done
    } > "$1/docs/forge/plans/active.md"
    git -C "$1" add -A && git -C "$1" commit -q -m plan
  }
  PLAN_REL=docs/dforge/plans/active.md
  make_legacy "$TMP/mig-full"
  bash "$S/dforge-migrate" "$TMP/mig-full" >/dev/null 2>&1
  NEW=$(cat "$TMP/mig-full/$PLAN_REL" 2>/dev/null; printf x)
  make_legacy "$TMP/mig-old"
  OLD=$(cat "$TMP/mig-old/docs/forge/plans/active.md"; printf x)
  check "A9: control: an uninterrupted migrate rewrites the plan's prefixes" "$(grep -c 'dr-forge:\|dr-superpowers:' "$TMP/mig-full/$PLAN_REL")" "0"

  SHIM="$TMP/shim"
  mkdir -p "$SHIM"
  # awk stalls after half of an output that holds a rewritten prefix; mv
  # stalls before it renames onto the plan. The test then kills the group.
  cat > "$SHIM/awk" <<'EOF'
#!/usr/bin/env bash
buf=$(mktemp)
"$SHIM_REAL_AWK" "$@" > "$buf"; rc=$?
if grep -q 'dforge:' "$buf"; then
  size=$(wc -c < "$buf")
  head -c $((size / 2)) "$buf"
  : > "$SHIM_FLAG"
  sleep 120
  exit 1
fi
cat "$buf"; rm -f "$buf"
exit $rc
EOF
  cat > "$SHIM/mv" <<'EOF'
#!/usr/bin/env bash
for last; do :; done
case $last in
  */plans/active.md) : > "$SHIM_FLAG"; sleep 120; exit 1 ;;
esac
exec "$SHIM_REAL_MV" "$@"
EOF
  chmod +x "$SHIM/awk" "$SHIM/mv"

  killed_run() { # killed_run NAME — migrate the legacy repository NAME under the shims, killed once the shim stalls
    local dir=$TMP/$1 flag=$TMP/$1.flag i pid
    make_legacy "$dir"
    rm -f "$flag"
    PATH="$SHIM:$PATH" SHIM_REAL_AWK=$REAL_AWK SHIM_REAL_MV=$REAL_MV SHIM_FLAG=$flag setsid bash "$S/dforge-migrate" "$dir" >/dev/null 2>&1 &
    pid=$!
    PIDS_TO_KILL="$PIDS_TO_KILL -$pid"
    for i in $(seq 1 300); do [ -e "$flag" ] && break; sleep 0.1; done
    if [ -e "$flag" ]; then KILL_REACHED=yes; else KILL_REACHED=no; fi
    kill -KILL -- "-$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  }
  plan_state() { # plan_state DIR — old, new or other
    local got
    got=$(cat "$1/$PLAN_REL" 2>/dev/null; printf x)
    if [ "$got" = "$OLD" ]; then echo old; elif [ "$got" = "$NEW" ]; then echo new; else echo "other ($(wc -c < "$1/$PLAN_REL" 2>/dev/null) bytes)"; fi
  }
  killed_run mig-awk-kill
  check "A9: the rewrite was reached before the kill (awk stalled)" "$KILL_REACHED" "yes"
  case "$(plan_state "$TMP/mig-awk-kill")" in old | new) r=ok ;; *) r=$(plan_state "$TMP/mig-awk-kill") ;; esac
  check "A9: a plan rewrite killed while its text is half produced leaves the plan's old or new content" "$r" "ok"
  killed_run mig-mv-kill
  check "A9: the rewrite was reached before the kill (mv stalled)" "$KILL_REACHED" "yes"
  case "$(plan_state "$TMP/mig-mv-kill")" in old | new) r=ok ;; *) r=$(plan_state "$TMP/mig-mv-kill") ;; esac
  check "A9: a plan rewrite killed just before it lands leaves the plan's old or new content" "$r" "ok"
fi

# =====================================================================
# A15: bash 3.2
# =====================================================================
if [ "$IS_WINDOWS" = 1 ]; then
  skip "A15: no Linux containers on Windows"
elif ! command -v docker >/dev/null 2>&1 || ! timeout 30 docker info >/dev/null 2>&1; then
  skip "A15: docker is unavailable"
elif ! docker image inspect bash:3.2 >/dev/null 2>&1 && ! timeout 300 docker pull -q bash:3.2 >/dev/null 2>&1; then
  skip "A15: bash:3.2 is unavailable"
else
  C="$TMP/a15"
  mkdir -p "$C/home" "$C/work"
  # A transcript with two background shells that never finish: one a service,
  # one work.
  printf '%s\n' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_dev","name":"Bash","input":{"description":"Dev server","command":"npm run dev","run_in_background":true}},{"type":"tool_use","id":"toolu_build","name":"Bash","input":{"description":"Build","command":"make build","run_in_background":true}}]}}' \
    '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_dev","content":"Command running in background with ID: d1. Output is being written to: /tmp/d1.output."},{"type":"tool_result","tool_use_id":"toolu_build","content":"Command running in background with ID: d2. Output is being written to: /tmp/d2.output."}]}}' \
    > "$C/transcript.jsonl"
  KEY=$(printf '%s' /t/work | tr -c 'A-Za-z0-9' '-')
  mkdir -p "$C/home/.claude/dforge/sessions" "$C/home/.claude/projects/$KEY"
  cp "$C/transcript.jsonl" "$C/home/.claude/projects/$KEY/sess-15.jsonl"
  printf '{"session_id":"sess-15","transcript_path":"/t/home/.claude/projects/%s/sess-15.jsonl"}\n' "$KEY" > "$C/home/.claude/dforge/sessions/$KEY.json"

  cat > "$C/inner.sh" <<'EOF'
export HOME=/t/home
cd /t/work
printf '%s\n' "$BASH_VERSION" > /t/version
bash /r/plugins/dforge/scripts/context-size > /t/context.out 2>&1; echo $? > /t/context.rc
bash /r/plugins/dforge/scripts/in-flight > /t/inflight.out 2>&1; echo $? > /t/inflight.rc
bash /r/plugins/dforge/scripts/task-step > /t/step-usage.out 2>&1; echo $? > /t/step-usage.rc
{ sed -n '/^suite_failing_lines() {$/,/^}$/p' /r/plugins/dforge/scripts/task-step
  sed -n '/^suite_fail_set() {$/,/^}$/p' /r/plugins/dforge/scripts/task-step; } > /t/fail-set.sh
: > /t/empty.log
bash -uc '. /t/fail-set.sh; a=$(suite_fail_set /t/empty.log 7); b=$(suite_fail_set /t/empty.log 7); printf "%s\n%s\n" "$a" "$b"' > /t/marker.out 2>&1
echo $? > /t/marker.rc
exit 0
EOF
  timeout 300 docker run --rm --name "$NAME15" -v "$ROOT":/r:ro -v "$C":/t bash:3.2 \
    sh -c 'timeout 120 apk add --no-cache jq >/dev/null 2>&1 || exit 77; timeout 200 bash /t/inner.sh' >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 77 ]; then
    skip "A15: jq could not be installed in bash:3.2"
  else
    check "A15: the container ran bash 3.2" "$rc|$(cut -c1-4 "$C/version" 2>/dev/null)" "0|3.2."
    errors() { grep -cE 'unbound variable|command not found|bad substitution|syntax error' "$1" 2>/dev/null; }
    check "A15: context-size with no arguments: no unbound-variable or command-not-found error" "$(errors "$C/context.out")" "0"
    check "A15: context-size with no arguments ran to an exit code of the documented set" "$(case "$(cat "$C/context.rc" 2>/dev/null)" in 0 | 3 | 5 | 6) echo ok ;; *) cat "$C/context.rc" "$C/context.out" ;; esac)" "ok"
    check "A15: in-flight: no unbound-variable or command-not-found error" "$(errors "$C/inflight.out")" "0"
    check "A15: in-flight reads the transcript and lists both background shells" "$(grep -c 'shell d[12] ' "$C/inflight.out")|$(cat "$C/inflight.rc" 2>/dev/null)" "2|1"
    check "A15: task-step: loads and prints its usage with no unbound-variable or command-not-found error" "$(errors "$C/step-usage.out")|$(cat "$C/step-usage.rc" 2>/dev/null)" "0|2"
    check "A15: task-step's unnamed-failure marker: no unbound-variable or command-not-found error" "$(errors "$C/marker.out")|$(cat "$C/marker.rc" 2>/dev/null)" "0|0"
    check "A15: task-step's unnamed-failure marker names the exit and a process id" \
      "$(grep -cE '^command exit 7 \(unnamed [0-9]+-[0-9]+\)$' "$C/marker.out")" "2"
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
