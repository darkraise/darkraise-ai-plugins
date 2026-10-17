#!/usr/bin/env bash
# An auto run is one state file in the primary checkout's self-ignoring sdd/
# directory, bound to one session: another session sees no run, a stale run
# gives way, and each command changes only what it names.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR="$HERE/../scripts/auto-run"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
STATE="$REPO/.dforge/sdd/auto-run.json"
SPEC=docs/dforge/specs/2026-10-13-widget-design.md
ar() { (cd "$REPO" && bash "$AR" "$@"); }
field() { jq -r --arg f "$1" '.[$f] | tostring' "$STATE"; }
# A session's by-id record and transcript, written now or at a touch -d time.
live() { # live <session> [touch -d argument]
  local rec="$HOME/.claude/dforge/sessions/by-id/$1.json" tp="$HOME/.claude/projects/p/$1.jsonl"
  mkdir -p "$(dirname "$rec")" "$(dirname "$tp")"
  printf '{}\n' > "$tp"
  [ -z "${2:-}" ] || touch -d "$2" "$tp"
  jq -n --arg tp "$tp" '{transcript_path: $tp}' > "$rec"
}

# --- start ---
out=$(ar start --spec "$SPEC" 2>&1); status=$?
check "start without a session: exit 2" "$status" "2"
check "start without a session: says why" "$(grep -c 'no session id' <<<"$out")" "1"
out=$(ar --session s-1 start --spec "$SPEC" 2>&1); status=$?
check "start: exit 0" "$status" "0"
reg="docs/dforge/registers/$(date +%Y-%m-%d)-widget-auto.md"
check "start: prints the register it created" "$out" "$reg"
check "start: the register has the table header" "$(grep -c '^| # | Item | Assigned | Acceptance | State | Note |$' "$REPO/$reg")" "1"
check "start: the register covers the spec" "$(grep -c "^\*\*Covers:\*\* $SPEC$" "$REPO/$reg")" "1"
check "start: active, bound, based on main" "$(field active) $(field session) $(field base)" "true s-1 main"
check "start: phase spec, regime normal" "$(field phase) $(field regime)" "spec normal"
check "start: nothing pending" "$(field pending)" "null"
check "start: the state file is ignored by git" "$(git -C "$REPO" status --porcelain -- .dforge | grep -c .)" "0"
check "start: sdd ignores everything in it" "$(cat "$REPO/.dforge/sdd/.gitignore")" "*"

# --- binding ---
ar --session s-2 status >/dev/null 2>&1; status=$?
check "another session: no run (exit 3)" "$status" "3"
ar --session s-2 stop >/dev/null 2>&1; status=$?
check "another session cannot stop it" "$status:$(field active)" "3:true"
out=$(ar --session s-1 status); status=$?
check "status: exit 0" "$status" "0"
check "status: one line" "$out" "auto run: spec — regime normal — pending none — 0 compactions — 0 resumes — 0 pending decisions — spec $SPEC — plan none — base main — register $reg"
check "pending: none" "$(ar --session s-1 pending)" "none"
check "the environment names the session" "$(cd "$REPO" && CLAUDE_CODE_SESSION_ID=s-1 bash "$AR" pending)" "none"

# --- a second start ---
live s-1
ar --session s-2 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a second start while the first is live: exit 4" "$status:$(field session)" "4:s-1"
live s-1 '2 hours ago'
ar --session s-2 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a stale run gives way" "$status:$(field session):$(field register)" "0:s-2:docs/r.md"
mkdir -p "$HOME/.claude/projects/q"
printf '{}\n' > "$HOME/.claude/projects/q/s-2.jsonl"
ar --session s-1 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a live transcript without a record still counts" "$status:$(field session)" "4:s-2"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "--force replaces a live run" "$status:$(field session)" "0:s-1"

# --- a start from a linked worktree ---
git -C "$REPO" worktree add -q -b side "$TMP/side"
out=$(cd "$TMP/side" && bash "$AR" --session s-5 start --spec "$SPEC" --force 2>&1); status=$?
check "worktree: the register is created in that checkout" "$status:$([ -f "$TMP/side/$reg" ] && echo yes)" "0:yes"
check "worktree: the state stays in the primary checkout" "$(field session) $(field base)" "s-5 side"
git -C "$REPO" worktree add -q --detach "$TMP/loose"
(cd "$TMP/loose" && bash "$AR" --session s-6 start --spec "$SPEC" --register docs/r.md --force >/dev/null)
check "a detached HEAD has no base" "$(field base)" "null"
check "a detached HEAD: status says none" "$(ar --session s-6 status | grep -c 'base none')" "1"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null

# --- progress ---
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase execute
check "attach and phase" "$(field plan) $(field phase)" "docs/plan.md execute"
ar --session s-1 phase later >/dev/null 2>&1; status=$?
check "an unknown phase: exit 2" "$status:$(field phase)" "2:execute"

# --- decisions and rulings ---
ar --session s-1 decision add --id d1 --question "Which store?" --options "sqlite | files" --opus-reason "the spec is silent" --task 3
ar --session s-1 decision add --id d2 --question "Retry count?"
check "decision list" "$(ar --session s-1 decision list | jq -r '.id' | paste -sd, -)" "d1,d2"
check "a decision keeps its fields" "$(ar --session s-1 decision list | jq -r 'select(.id == "d1") | "\(.options)|\(.opusReason)|\(.task)"')" "sqlite | files|the spec is silent|3"
ar --session s-1 decision add --id d1 --question "Which store, again?"
check "adding an id again replaces it" "$(ar --session s-1 decision list | jq -r 'select(.id == "d1") | .question')" "Which store, again?"
ar --session s-1 decision clear --id d1
check "clear one" "$(ar --session s-1 decision list | jq -r '.id' | paste -sd, -)" "d2"
ar --session s-1 decision clear
check "clear all" "$(ar --session s-1 decision list | grep -c .)" "0"
ar --session s-1 ruling add "Fable: keep the sqlite store — cost if wrong: one migration"
ar --session s-1 ruling add "Opus: three retries"
check "ruling list" "$(ar --session s-1 ruling list | paste -sd'|' -)" "Fable: keep the sqlite store — cost if wrong: one migration|Opus: three retries"

# --- clears ---
ar --session s-1 clear --phase >/dev/null 2>&1; status=$?
check "clear without a handoff file: exit 1, nothing pending" "$status:$(field pending)" "1:null"
mkdir -p "$REPO/.dforge/handoff"
cat > "$REPO/.dforge/handoff/latest.md" <<'EOF'
# Handoff

## Next session

**Status:** plan saved
**Next:** execute the plan

Launch in `/work/repo`:

```
claude --model sonnet --effort high
```

Paste as the first prompt:

```
Execute docs/plan.md with dforge:subagent-driven-development.
```
EOF
ar --session s-1 clear --phase; status=$?
check "clear --phase: exit 0" "$status" "0"
check "clear --phase: pending clear, awaiting a rebind" "$(field pending) $(field rebind)" "clear true"
check "clear --phase: the first prompt" "$(field resumePrompt)" "Execute docs/plan.md with dforge:subagent-driven-development."
check "clear --phase: the launch" "$(jq -r '.launch | "\(.model) \(.effort)"' "$STATE")" "sonnet high"
check "clear --phase: not a self-resume" "$(field resumes)" "0"

# --- rebind ---
ar --session s-1 rebind --to s-9; status=$?
check "rebind: exit 0" "$status" "0"
check "rebind: the cleared session is bound" "$(ar --session s-9 pending)" "resume"
ar --session s-1 status >/dev/null 2>&1; status=$?
check "rebind: the old session is not" "$status" "3"
check "rebind: nothing awaits a rebind" "$(field rebind)" "false"
ar --session s-9 resumed
check "resumed: nothing pending" "$(field pending)" "null"
ar --session s-7 rebind --to s-7 >/dev/null 2>&1; status=$?
check "rebind without a clear: exit 4" "$status:$(field session)" "4:s-9"

# --- self-resumes ---
ar --session s-9 clear; ar --session s-9 rebind --to s-10
check "a clear without --phase counts" "$(field resumes)" "1"
ar --session s-10 task-complete
check "task-complete resets the count" "$(field resumes)" "0"
ar --session s-10 clear; ar --session s-10 rebind --to s-11
ar --session s-11 clear; ar --session s-11 rebind --to s-12
ar --session s-12 clear >/dev/null 2>&1; status=$?
check "the third self-resume in a row stops the run" "$status:$(field active)" "5:false"
check "the stop says why" "$(field stopped)" "three self-resumes without a completed task"

# --- compactions and failures ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 compacted
check "compacted: counted, after-compact pending" "$(field compactions) $(field pending)" "1 after-compact"
ar --session s-1 failure --reason "vetoed"; status=$?
check "a first failure: exit 0, counted" "$status:$(field failures):$(field active)" "0:1:true"
ar --session s-1 compacted
check "a compaction resets the failures" "$(field failures)" "0"
ar --session s-1 failure; ar --session s-1 failure --reason "refused twice"; status=$?
check "a second failure in a row stops the run" "$status:$(field active):$(field stopped)" "5:false:refused twice"

# --- concurrent counts: each increment is read and written under one lock ---
# The wrapper slows every read of a count, so two callers that read before
# they write both see the old value.
SLOW_JQ="$TMP/slow-jq"
printf '#!/usr/bin/env bash\ncase " $* " in *" f failures "*|*" f resumes "*) sleep 1 ;; esac\nexec jq "$@"\n' > "$SLOW_JQ"
chmod +x "$SLOW_JQ"
for lock in flock no-such-flock; do
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  DFORGE_JQ=$SLOW_JQ DFORGE_FLOCK=$lock ar --session s-1 failure >/dev/null 2>&1 &
  DFORGE_JQ=$SLOW_JQ DFORGE_FLOCK=$lock ar --session s-1 failure >/dev/null 2>&1 &
  wait
  check "$lock: two failures at once stop the run" "$(field failures):$(field active)" "2:false"
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  DFORGE_JQ=$SLOW_JQ DFORGE_FLOCK=$lock ar --session s-1 clear >/dev/null 2>&1 &
  DFORGE_JQ=$SLOW_JQ DFORGE_FLOCK=$lock ar --session s-1 clear >/dev/null 2>&1 &
  wait
  check "$lock: two clears at once count two self-resumes" "$(field resumes):$(field pending)" "2:clear"
done
check "no flock: the lock directory is gone" "$([ -e "$STATE.lockd" ] && echo left || echo gone)" "gone"
mkdir "$STATE.lockd"
DFORGE_FLOCK=no-such-flock ar --session s-1 task-complete; status=$?
check "no flock: a lock its holder left behind is taken after the wait" "$status:$(field resumes)" "0:0"
check "no flock: and released" "$([ -e "$STATE.lockd" ] && echo left || echo gone)" "gone"

# --- stop ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 stop --reason "owner asked"
check "stop: inactive with the reason" "$(field active):$(field stopped)" "false:owner asked"
ar --session s-1 status >/dev/null 2>&1; status=$?
check "stop: no run is bound any more" "$status" "3"
ar --session s-1 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a stopped run never blocks a start" "$status" "0"
ar --session s-1 stop
check "stop without a reason: finished" "$(field stopped)" "null"

# --- the rules (reference/auto-run.md §The budget line) ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
verdict() { ar --session s-1 verdict --budget 465000 --window 800000 "$@"; }
out=$(verdict --tokens 464999); status=$?
check "normal: under the budget" "$status:$out" "0:ok 465000 normal"
check "normal: ok leaves nothing pending" "$(field pending)" "null"
out=$(verdict --tokens 465000); status=$?
check "normal: at the budget, compact" "$status:$out" "6:compact 465000 normal"
check "compact is pending" "$(field pending)" "compact"
out=$(verdict --tokens 185000 --wave 3); status=$?
check "a wave of three reserves two tasks" "$status:$out" "6:compact 185000 normal"
out=$(verdict --tokens 184999 --wave 3)
check "a narrower probe that fits cancels the compaction" "$out:$(field pending)" "ok 185000 normal:null"
ar --session s-1 compacted
out=$(verdict --tokens 395249)
check "after a compaction under 85% of the budget: normal" "$out:$(field pending)" "ok 465000 normal:null"
ar --session s-1 compacted
out=$(verdict --tokens 395250)
check "after a compaction at 85% of the budget: high" "$out" "ok 720000 high"
out=$(verdict --tokens 719999)
check "high: under 90% of the window" "$out" "ok 720000 high"
out=$(verdict --tokens 720000); status=$?
check "high: at 90% of the window, compact" "$status:$out" "6:compact 720000 high"
ar --session s-1 compacted
out=$(verdict --tokens 679999)
check "after a compaction under 85% of the window: high stays" "$out" "ok 720000 high"
ar --session s-1 compacted
out=$(verdict --tokens 100000)
check "after a small compaction: back to normal" "$out" "ok 465000 normal"
ar --session s-1 compacted
out=$(verdict --tokens 680000); status=$?
check "after a compaction at 85% of the window: handoff" "$status:${out%% *}" "5:handoff"
check "a handoff stays pending" "$(field pending)" "handoff"
out=$(verdict --tokens 10000); status=$?
check "a re-probe before clear still hands off" "$status:${out%% *}" "5:handoff"
ar --session s-1 clear --phase
out=$(verdict --tokens 10000); status=$?
check "a pending clear answers handoff" "$status:${out%% *}" "5:handoff"
ar --session s-1 rebind --to s-1
ar --session s-1 compacted
out=$(ar --session s-1 verdict --tokens 260000 --budget 300000 --window 400000)
check "another budget and window" "$out" "ok 360000 high"
ar --session s-x verdict --tokens 1 --budget 1 --window 1 >/dev/null 2>&1; status=$?
check "verdict for another session: exit 3" "$status" "3"
ar --session s-1 verdict --tokens 1 --budget 1 >/dev/null 2>&1; status=$?
check "verdict without a window: exit 2" "$status" "2"

# --- after-compact measures the session it names ---
mkdir -p "$HOME/.claude"
printf '{"autoCompactWindow": 800000}\n' > "$HOME/.claude/settings.json"
live s-1
T="$HOME/.claude/projects/p/s-1.jsonl"
asst() { printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' "$1"; }
after() { (cd "$REPO" && CLAUDE_CODE_SESSION_ID=s-other DFORGE_BUDGET=465000 bash "$AR" --session s-1 after-compact); }
ar --session s-1 compacted
asst 30000 > "$T"
out=$(after); status=$?
check "after-compact: a small context continues" "$status:$out" "0:continue — 30k after compaction; regime normal"
check "after-compact: nothing pending" "$(field pending)" "null"
ar --session s-1 compacted
asst 700000 > "$T"
out=$(after); status=$?
check "after-compact: 85% of the window hands off" "$status:${out%% *}" "5:handoff"
check "after-compact: the handoff stays pending" "$(field pending)" "handoff"
ar --session s-1 compacted
printf '{}\n' > "$T"
out=$(after); status=$?
check "after-compact: an unknown size continues and says to record it" "$status:${out%%;*}" "0:continue — the size after compaction is unknown"
check "after-compact: unknown leaves nothing pending" "$(field pending)" "null"

# --- concurrent updates ---
if command -v flock >/dev/null 2>&1; then
  ar --session s-1 stop
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  for i in $(seq 1 12); do ar --session s-1 ruling add "r$i" & done
  wait
  check "concurrent updates all land" "$(ar --session s-1 ruling list | grep -c .)" "12"
fi

# --- after-compact never overwrites a pending action it did not book ---
asst 30000 > "$T"
ar --session s-1 clear --phase
out=$(after); status=$?
check "after-compact: a pending clear is a handoff in progress" "$status:${out%% *}:$(field pending):$(field rebind)" "5:handoff:clear:true"
printf '{}\n' > "$T"
out=$(after); status=$?
check "after-compact: a pending clear hands off when the size is unknown too" "$status:${out%% *}:$(field pending)" "5:handoff:clear"
ar --session s-1 rebind --to s-1
asst 30000 > "$T"
out=$(after); status=$?
check "after-compact: a pending resume is measured, not written" "$status:${out%% *}:$(field pending)" "0:continue:resume"
asst 700000 > "$T"
out=$(after); status=$?
check "after-compact: a large size with a pending resume hands off without writing" "$status:${out%% *}:$(field pending)" "5:handoff:resume"
ar --session s-1 resumed
asst 30000 > "$T"
out=$(after); status=$?
check "after-compact: with nothing pending it only measures" "$status:${out%% *}:$(field pending)" "0:continue:null"
ar --session s-1 compacted
asst 700000 > "$T"
after >/dev/null
asst 30000 > "$T"
out=$(after); status=$?
check "after-compact: a pending handoff stays a handoff" "$status:${out%% *}:$(field pending)" "5:handoff:handoff"

# --- resumed ends the failure count ---
ar --session s-1 clear --phase
ar --session s-1 rebind --to s-1
ar --session s-1 failure --reason "model refused"
check "a failure after a rebind is counted" "$(field failures)" "1"
ar --session s-1 resumed
check "resumed resets the failures" "$(field failures):$(field pending)" "0:null"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
