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
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
STATE="$REPO/.dforge/sdd/auto-run.json"
SPEC=docs/dforge/specs/2026-10-13-widget-design.md
beat() { # beat <session> [age in seconds]: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(( $(date +%s) - ${2:-0} ))" > "$f"
}
# Every call through ar has a live cockpit in the session it names.
ar() {
  [ "${1:-}" != --session ] || beat "$2"
  (cd "$REPO" && bash "$AR" "$@")
}
# The same, from the linked worktree $TMP/side (made below): where an auto
# run's execution happens.
side() { (cd "$TMP/side" && bash "$AR" "$@"); }
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
check "start: no stalls, no compactions since a task" "$(field stalls):$(field stalledAt):$(field compactionsSinceTask)" "0:null:0"
check "start: the state file is ignored by git" "$(git -C "$REPO" status --porcelain -- .dforge | grep -c .)" "0"
check "start: sdd ignores everything in it" "$(cat "$REPO/.dforge/sdd/.gitignore")" "*"

# A cloned repository controls .dforge/sdd/, so its ignore is never written
# through a symbolic link.
git init -q -b main "$TMP/linked"
git -C "$TMP/linked" commit -q --allow-empty -m init
mkdir -p "$TMP/linked/.dforge/sdd" "$TMP/outside"
ln -s "$TMP/outside/planted" "$TMP/linked/.dforge/sdd/.gitignore"
beat s-link
(cd "$TMP/linked" && bash "$AR" --session s-link start --spec "$SPEC" >/dev/null 2>&1)
check "start: linked ignore never written through" "$([ -e "$TMP/outside/planted" ] && echo yes || echo no)" "no"

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
beat s-1 7200
ar --session s-2 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a stale run gives way" "$status:$(field session):$(field register)" "0:s-2:docs/r.md"
mkdir -p "$HOME/.claude/projects/q"
printf '{}\n' > "$HOME/.claude/projects/q/s-2.jsonl"
rm -f "$HOME/.claude/dforge/sessions/cockpit/s-2"
ar --session s-1 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a live transcript without a record still counts" "$status:$(field session)" "4:s-2"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "--force replaces a live run" "$status:$(field session)" "0:s-1"

# --- a start needs a live cockpit in its session ---
(cd "$REPO" && bash "$AR" --session s-3 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>"$TMP/err"); status=$?
check "start without a cockpit heartbeat: exit 2, the run unchanged" "$status:$(field session)" "2:s-1"
check "start without a cockpit heartbeat: says why" "$(grep -c 'no live cockpit in this session' "$TMP/err")" "1"
beat s-3 181
(cd "$REPO" && bash "$AR" --session s-3 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1); status=$?
check "a heartbeat older than 180 seconds: exit 2" "$status:$(field session)" "2:s-1"
beat s-1 181
ar --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose cockpit heartbeat is older than 180 seconds is stale" "$status:$(field session)" "0:s-3"

# --- the heartbeat's age, on a clock that stands still ---
# A fixed clock, so the 180-second boundary cannot slip a second between
# writing a heartbeat and reading it.
NOW=$(date +%s)
CLOCK="$TMP/clock"
mkdir -p "$CLOCK"
printf '#!/usr/bin/env bash\nif [ "$*" = +%%s ]; then echo %s; else exec %s "$@"; fi\n' "$NOW" "$(command -v date)" > "$CLOCK/date"
chmod +x "$CLOCK/date"
stamp() { # stamp <session> <seconds before NOW; negative is ahead of it>
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(( NOW - $2 ))" > "$f"
}
at_now() { (cd "$REPO" && PATH="$CLOCK:$PATH" bash "$AR" "$@"); }
age_of() { (PATH="$CLOCK:$PATH"; . "$HERE/../scripts/lib/auto-run.sh"; ar_beat_age "$1") 2>/dev/null || echo fails; }
stamp s-4 180
check "a heartbeat 180 seconds old: age 180" "$(age_of s-4)" "180"
stamp s-4 -5
check "a heartbeat 5 seconds ahead (clock skew): age 0" "$(age_of s-4)" "0"
stamp s-4 -180
check "a heartbeat 180 seconds ahead: age 0" "$(age_of s-4)" "0"
stamp s-4 -181
check "a heartbeat 181 seconds ahead: no age" "$(age_of s-4)" "fails"
stamp s-4 180
at_now --session s-4 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "start with a heartbeat 180 seconds old: exit 0" "$status:$(field session)" "0:s-4"
stamp s-3 0
at_now --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose heartbeat is 180 seconds old is live" "$status:$(field session)" "4:s-4"
stamp s-4 -5
at_now --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose heartbeat is a few seconds ahead is live" "$status:$(field session)" "4:s-4"
stamp s-4 -3600
at_now --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose heartbeat is an hour ahead is stale" "$status:$(field session)" "0:s-3"
at_now --session s-4 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "start with its own heartbeat an hour ahead: no live cockpit" "$status:$(field session)" "2:s-3"
ar --session s.7 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "the beat helper names the file as ar_beat_file does" "$status:$(field session)" "0:s.7"

# --- a start from a linked worktree ---
git -C "$REPO" worktree add -q -b side "$TMP/side"
beat s-5
out=$(cd "$TMP/side" && bash "$AR" --session s-5 start --spec "$SPEC" --force 2>&1); status=$?
check "worktree: the register is created in that checkout" "$status:$([ -f "$TMP/side/$reg" ] && echo yes)" "0:yes"
check "worktree: the state stays in the primary checkout" "$(field session) $(field base)" "s-5 side"
side --session s-5 phase execute; status=$?
check "a run started in a linked worktree: phase execute there passes" "$status:$(field phase)" "0:execute"
git -C "$REPO" worktree add -q --detach "$TMP/loose"
beat s-6
(cd "$TMP/loose" && bash "$AR" --session s-6 start --spec "$SPEC" --register docs/r.md --force >/dev/null)
check "a detached HEAD has no base" "$(field base)" "null"
check "a detached HEAD: status says none" "$(ar --session s-6 status | grep -c 'base none')" "1"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null

# --- progress ---
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase execute 2>"$TMP/err"; status=$?
check "phase execute in the primary checkout: exit 4, phase unchanged" "$status:$(field phase)" "4:spec"
check "phase execute in the primary checkout: says to make the worktree" "$(grep -c 'create the execution worktree first (dforge:using-git-worktrees)' "$TMP/err")" "1"
side --session s-1 phase execute; status=$?
check "phase execute from a linked worktree: exit 0" "$status" "0"
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
# The cockpit calls rebind from the session that replaced the cleared one.
ar --session s-9 clear --phase
ar --session s-20 rebind --to s-20; status=$?
check "rebind from the new session: exit 0" "$status:$(field session):$(field pending)" "0:s-20:resume"
ar --session s-20 resumed
ar --session s-20 clear --phase; ar --session s-9 rebind --to s-9; ar --session s-9 resumed

# --- self-resumes ---
ar --session s-9 clear; ar --session s-9 rebind --to s-10
check "a clear without --phase counts" "$(field resumes)" "1"
side --session s-10 task-complete
check "task-complete resets the count" "$(field resumes)" "0"
ar --session s-10 clear; ar --session s-10 rebind --to s-11
ar --session s-11 clear; ar --session s-11 rebind --to s-12
ar --session s-12 clear >/dev/null 2>&1; status=$?
check "the third self-resume in a row stops the run" "$status:$(field active)" "5:false"
check "the stop says why" "$(field stopped)" "3 self-resumes without a completed task"

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
# An ownerless lock is a claim in progress until it is a minute old.
mkdir "$STATE.lockd"
DR_LOCK_TENTHS=5 DFORGE_FLOCK=no-such-flock side --session s-1 ruling add 'past a fresh claim' 2>/dev/null; status=$?
check "no flock: a lock still being claimed is never taken" "$status:$(jq -r '.rulings | length' "$STATE")" "1:0"
touch -t 202001010000 "$STATE.lockd"
DR_LOCK_TENTHS=5 DFORGE_FLOCK=no-such-flock side --session s-1 task-complete; status=$?
check "no flock: a lock its holder left behind is taken" "$status:$(field resumes)" "0:0"
check "no flock: and released" "$([ -e "$STATE.lockd" ] && echo left || echo gone)" "gone"
# A held lock is taken over only from an owner that provably exited: a live
# but slow holder keeps it, and the waiter gives up rather than writing.
sleep 30 & live_holder=$!
mkdir "$STATE.lockd" && printf '%s\n' "$live_holder" > "$STATE.lockd/pid" && uname -n > "$STATE.lockd/host"
DR_LOCK_TENTHS=5 DFORGE_FLOCK=no-such-flock side --session s-1 ruling add 'past a live holder' 2>/dev/null; status=$?
check "no flock: a live holder's lock is never taken" "$status:$(jq -r '.rulings | length' "$STATE")" "1:0"
kill "$live_holder"; wait "$live_holder" 2>/dev/null
DR_LOCK_TENTHS=5 DFORGE_FLOCK=no-such-flock side --session s-1 ruling add 'past a dead holder'; status=$?
check "no flock: a dead holder's lock is taken" "$status:$(jq -r '.rulings | length' "$STATE")" "0:1"
check "no flock: and released after" "$([ -e "$STATE.lockd" ] && echo left || echo gone)" "gone"
mkdir "$STATE.lockd" && uname -n > "$STATE.lockd/host" && touch -t 202001010000 "$STATE.lockd"
DR_LOCK_TENTHS=5 DFORGE_FLOCK=no-such-flock side --session s-1 ruling add 'past a claim killed before its pid'; status=$?
check "no flock: a claim killed before its pid is taken" "$status:$(jq -r '.rulings | length' "$STATE")" "0:2"
# A reclaimer killed inside its guard leaves the guard; once old it is no bar.
sleep 0 & dead_holder=$!
wait "$dead_holder"
mkdir "$STATE.lockd" && printf '%s\n' "$dead_holder" > "$STATE.lockd/pid" && uname -n > "$STATE.lockd/host"
mkdir "$STATE.lockd.reclaim"
DR_LOCK_TENTHS=5 DFORGE_FLOCK=no-such-flock side --session s-1 ruling add 'past a fresh guard' 2>/dev/null; status=$?
check "no flock: a fresh reclaim guard holds off a reclaim" "$status:$(jq -r '.rulings | length' "$STATE")" "1:2"
touch -t 202001010000 "$STATE.lockd.reclaim"
DR_LOCK_TENTHS=5 DFORGE_FLOCK=no-such-flock side --session s-1 ruling add 'past a stale guard'; status=$?
check "no flock: a stale reclaim guard is cleared" "$status:$(jq -r '.rulings | length' "$STATE"):$([ -e "$STATE.lockd" ] && echo left || echo gone):$([ -e "$STATE.lockd.reclaim" ] && echo left || echo gone)" "0:3:gone:gone"

# The binding is checked again under the lock, so a caller that passed the
# first check before the run moved to another session changes nothing.
ar --session s-2 start --spec "$SPEC" --register docs/r.md --force >/dev/null
( cd "$REPO" && . "$HERE/../scripts/lib/context.sh" && . "$HERE/../scripts/lib/auto-run.sh" && AR_SESSION=s-1 ar_stop 'from s-1' ) 2>/dev/null
status=$?
check "an update for a session the run left is refused" "$status:$(field active):$(field session)" "3:true:s-2"

# --- a start writes under the same lock as an update ---
# The holder reads the state, keeps the lock two seconds, then writes back what
# it read, as an update does: a start that does not wait for it is lost.
# held <name>: waits up to 10 s for the holder to touch $STATE.ready, which it
# does once it holds the lock; on timeout it fails <name> and stops the holder,
# so the case cannot hang. The flock holder's bash -c child keeps the lock and
# writes $STATE after flock itself is killed, so the children go first.
held() {
  local i
  for i in $(seq 100); do
    [ -e "$STATE.ready" ] && return 0
    sleep 0.1
  done
  check "$1" "the holder never took the lock" "taken"
  pkill -P "$holder" 2>/dev/null
  kill "$holder" 2>/dev/null
  wait
  return 1
}
for lock in flock no-such-flock; do
  [ "$lock" = no-such-flock ] || command -v flock >/dev/null 2>&1 || continue
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  rm -f "$STATE.ready"
  if [ "$lock" = flock ]; then
    flock "$STATE.lock" bash -c 'touch "$1.ready"; s=$(cat "$1"); sleep 2; jq ".rulings = [\"held\"]" <<<"$s" > "$1.held" && mv -f "$1.held" "$1"' _ "$STATE" &
  else
    mkdir "$STATE.lockd"
    touch "$STATE.ready"
    (s=$(cat "$STATE"); sleep 2; jq '.rulings = ["held"]' <<<"$s" > "$STATE.held" && mv -f "$STATE.held" "$STATE"; rmdir "$STATE.lockd") &
  fi
  holder=$!
  held "$lock: a start waits for the lock" || continue
  DFORGE_FLOCK=$lock ar --session s-2 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  wait
  check "$lock: a start waits for the lock" "$(field session):$(field rulings)" "s-2:[]"
done

# --- a start that is not forced re-checks for a live run under the lock ---
# s-1's run is stopped, so s-2's first look finds none. While s-2's start waits
# for the lock, the holder makes s-1's run live again, as a start that got the
# lock first would: s-2 must see it, not replace it.
for lock in flock no-such-flock; do
  [ "$lock" = no-such-flock ] || command -v flock >/dev/null 2>&1 || continue
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  ar --session s-1 stop >/dev/null
  rm -f "$STATE.ready"
  if [ "$lock" = flock ]; then
    flock "$STATE.lock" bash -c 'touch "$1.ready"; sleep 2; jq ".active = true" "$1" > "$1.held" && mv -f "$1.held" "$1"' _ "$STATE" &
  else
    mkdir "$STATE.lockd"
    touch "$STATE.ready"
    (sleep 2; jq '.active = true' "$STATE" > "$STATE.held" && mv -f "$STATE.held" "$STATE"; rmdir "$STATE.lockd") &
  fi
  holder=$!
  held "$lock: a start that waited for the lock finds the run made live meanwhile" || continue
  DFORGE_FLOCK=$lock ar --session s-2 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
  wait
  check "$lock: a start that waited for the lock finds the run made live meanwhile" "$status:$(field session):$(field active)" "4:s-1:true"
done

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

# --- an ok verdict clears a resume the cockpit never confirmed ---
ar --session s-1 clear --phase
ar --session s-1 rebind --to s-1
check "rebind: a resume is pending" "$(field pending)" "resume"
out=$(verdict --tokens 10000); status=$?
check "an ok verdict clears a stale resume" "$status:${out%% *}:$(field pending)" "0:ok:null"

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

# --- the switch (reference/auto-run.md §The switch) ---
ar --session s-1 stop
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 switch >/dev/null 2>&1; status=$?
check "switch without a plan: exit 4, nothing pending" "$status:$(field pending)" "4:null"
ar --session s-1 attach --plan docs/other.md
ar --session s-1 switch >/dev/null 2>&1; status=$?
check "switch: a first prompt naming another plan: exit 4" "$status:$(field pending)" "4:null"
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch; status=$?
check "switch: exit 0, switch pending" "$status:$(field pending)" "0:switch"
check "switch: the phase moves to execute" "$(field phase)" "execute"
check "switch: the first prompt" "$(field resumePrompt)" "Execute docs/plan.md with dforge:subagent-driven-development."
check "switch: the launch" "$(jq -r '.launch | "\(.model) \(.effort)"' "$STATE")" "sonnet high"
check "switch: not a self-resume, no rebind" "$(field resumes):$(field rebind)" "0:false"
check "pending prints switch" "$(ar --session s-1 pending)" "switch"
ar --session s-1 compacted --switch
check "compacted --switch: counted, switch-resume pending" "$(field compactions):$(field pending)" "1:switch-resume"
check "the switch's compaction is not a final-phase one" "$(field finalCompacted)" "false"
ar --session s-1 resumed
check "resumed after a switch: after-compact is due" "$(field pending)" "after-compact"
asst 700000 > "$T"
out=$(after); status=$?
check "after a switch, an oversized context still hands off" "$status:${out%% *}" "5:handoff"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
ar --session s-1 compacted --switch
ar --session s-1 resumed
asst 30000 > "$T"
out=$(after); status=$?
check "after a switch, a small context continues" "$status:${out%% *}:$(field pending)" "0:continue:null"
ar --session s-1 compacted --what >/dev/null 2>&1; status=$?
check "compacted with another flag: exit 2" "$status" "2"

# --- the plan, final and finish phases never hand off ---
for phase in plan final finish; do
  ar --session s-1 phase "$phase"
  ar --session s-1 compacted
  asst 700000 > "$T"
  out=$(after); status=$?
  check "after-compact in $phase: 85% of the window continues" "$status:${out%% *}:$(field pending)" "0:continue:null"
done
side --session s-1 phase execute
ar --session s-1 compacted
out=$(after); status=$?
check "after-compact in execute: 85% of the window still hands off" "$status:${out%% *}" "5:handoff"

# --- once a final-phase compaction ran, every budget line is ok ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 phase final
out=$(verdict --tokens 465000); status=$?
check "final, before a compaction: at the budget, compact" "$status:${out%% *}" "6:compact"
ar --session s-1 compacted
check "a final-phase compaction is recorded" "$(field finalCompacted)" "true"
out=$(verdict --tokens 750000); status=$?
check "final, after a compaction: ok above the high limit" "$status:${out%% *}:$(field pending)" "0:ok:null"
ar --session s-1 phase finish
out=$(verdict --tokens 900000); status=$?
check "finish, after a final-phase compaction: ok" "$status:${out%% *}" "0:ok"

# --- Setup after the switch: setupDue and the primary-checkout guard ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
check "start: setup is not due" "$(field setupDue)" "false"
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
check "switch: setup is due" "$(field setupDue)" "true"
check "status: says setup is due" "$(ar --session s-1 status | grep -c ' — setup due$')" "1"
ar --session s-1 compacted --switch
ar --session s-1 resumed
asst 30000 > "$T"
out=$(after); status=$?
check "after a switch, continue names Setup" "$status:$out" "0:continue — 30k after compaction; regime normal; setup due: begin at the execution skill's Setup, worktree first"
ar --session s-1 phase execute 2>/dev/null; status=$?
check "phase execute in the primary checkout keeps setup due" "$status:$(field setupDue)" "4:true"
side --session s-1 phase execute
check "phase execute from a worktree settles Setup" "$(field setupDue)" "false"
check "status: no setup note once settled" "$(ar --session s-1 status | grep -c 'setup due')" "0"
ar --session s-1 switch
side --session s-1 task-complete; status=$?
check "task-complete in a worktree: exit 0, Setup settled" "$status:$(field setupDue):$(field active)" "0:false:true"
ar --session s-1 switch
ar --session s-1 phase final
check "phase final settles Setup" "$(field setupDue)" "false"
ar --session s-1 task-complete 2>"$TMP/err"; status=$?
check "task-complete in the primary checkout stops the run" "$status:$(field active):$(field stopped)" "5:false:a task was completed in the primary checkout"
check "task-complete in the primary checkout: says to end as Stopping says" "$(grep -c 'the run has stopped. End as reference/auto-run.md §Stopping says.' "$TMP/err")" "1"
for phase in spec plan; do
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  ar --session s-1 phase "$phase"
  ar --session s-1 stalled
  ar --session s-1 task-complete 2>"$TMP/err"; status=$?
  check "task-complete in the primary checkout in the $phase phase: the run goes on" "$status:$(field active):$(field stalls)" "0:true:0"
done
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
ar --session s-1 task-complete 2>/dev/null; status=$?
check "task-complete in the primary checkout in the execute phase stops the run" "$status:$(field phase):$(field active)" "5:execute:false"

# --- progress caps: compactions and stalls without a completed task ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 compacted
ar --session s-1 compacted
ar --session s-1 compacted; status=$?
check "plan-phase compactions are not counted" "$status:$(field active):$(field compactionsSinceTask)" "0:true:0"
ar --session s-1 switch
ar --session s-1 compacted --switch
check "the switch's compaction is not counted" "$(field compactionsSinceTask)" "0"
ar --session s-1 resumed
side --session s-1 phase execute
ar --session s-1 compacted
ar --session s-1 compacted
check "two execute compactions: counted, the run goes on" "$(field compactionsSinceTask):$(field active)" "2:true"
side --session s-1 task-complete
check "task-complete resets the compaction count" "$(field compactionsSinceTask)" "0"
ar --session s-1 compacted
ar --session s-1 compacted
ar --session s-1 compacted; status=$?
check "the third execute compaction without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:3 compactions without a completed task"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
before=$(date +%s)
ar --session s-1 stalled; status=$?
after_s=$(date +%s)
first=$(field stalledAt)
check "stalled: exit 0, counted" "$status:$(field stalls)" "0:1"
check "stalled: stalledAt is the epoch seconds of the call" "$([ "$first" -ge "$before" ] && [ "$first" -le "$after_s" ] && echo within || echo "outside $before..$after_s")" "within"
sleep 1
ar --session s-1 stalled
check "a later stall refreshes stalledAt" "$([ "$(field stalledAt)" -gt "$first" ] && echo later || echo same)" "later"
side --session s-1 task-complete
check "task-complete resets the stalls" "$(field stalls):$(field stalledAt)" "0:null"
ar --session s-1 stalled
ar --session s-1 stalled
ar --session s-1 stalled; status=$?
check "the third stall without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:3 stalls without a completed task"
ar --session s-1 stalled >/dev/null 2>&1; status=$?
check "stalled with no run bound: exit 3" "$status" "3"

# --- the progress fields: a state written before them, and the final phases ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
side --session s-1 phase execute
jq 'del(.stalls, .stalledAt, .compactionsSinceTask)' "$STATE" > "$STATE.old" && mv -f "$STATE.old" "$STATE"
ar --session s-1 stalled; status=$?
check "a state without the progress fields: a stall counts from zero" "$status:$(field stalls)" "0:1"
ar --session s-1 compacted; status=$?
check "a state without the progress fields: a compaction counts from zero" "$status:$(field compactionsSinceTask)" "0:1"
for phase in final finish; do
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  ar --session s-1 phase "$phase"
  ar --session s-1 compacted
  ar --session s-1 compacted
  ar --session s-1 compacted; status=$?
  check "$phase-phase compactions are not counted" "$status:$(field active):$(field compactionsSinceTask)" "0:true:0"
done

# --- after-compact: an unknown size still names a due Setup ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
ar --session s-1 compacted --switch
ar --session s-1 resumed
printf '{}\n' > "$T"
out=$(after); status=$?
check "after-compact: an unknown size with setup due names Setup" "$status:$out:$(field pending)" "0:continue — the size after compaction is unknown; record that with auto-run ruling add, and Claude Code's own compaction stays the backstop; setup due: begin at the execution skill's Setup, worktree first:null"

# --- every suite that runs the run-control scripts names its own session ---
# A subagent's shell carries the controller's CLAUDE_CODE_SESSION_ID, so a
# suite run there that leaves it set binds to the live auto run. A line runs a
# script when the path follows bash, "$, $ or starts a command; a line that
# only names it in quoted text, as a grep needle does, is not a match.
names='(context-size|auto-run|task-brief|review-package|repo-audit)([^[:alnum:]-]|$)'
runs='(bash[[:space:]]+|"\$|\$)[^[:space:]'"'"'`]*scripts/'"$names"'|(^|[;&|(])[[:space:]]*"?(\./)?scripts/'"$names"
sources='(^|[[:space:];&(])(\.|source)[[:space:]]+[^[:space:]]*scripts/lib/(auto-run|context)\.sh'
is_run() { grep -Eq "$runs|$sources" <<<"$1" && echo run || echo no; }
check "scan: bash and a path variable is a run" "$(is_run 'out=$(bash "$P/scripts/task-brief" docs/plan.md 1)')" "run"
check "scan: a path kept in a variable is a run" "$(is_run 'AR="$HERE/../scripts/auto-run"')" "run"
check "scan: a command that starts with the path is a run" "$(is_run '(cd "$REPO" && scripts/context-size --final)')" "run"
check "scan: sourcing context.sh is a run" "$(is_run '. "$HERE/../scripts/lib/context.sh"')" "run"
check "scan: a grep needle is not a run" "$(is_run "names \"x\" \"\$F\" '\`scripts/auto-run switch\` and end the turn'")" "no"
check "scan: another script of a similar name is not a run" "$(is_run 'bash "$P/scripts/auto-run-probe"')" "no"
named() { # named <suite> <variable>: the suite sets it with export or unsets it
  grep -Eq "^[[:space:]]*(export[[:space:]](.*[[:space:]])?$2=|unset[[:space:]](.*[[:space:]])?$2([;[:space:]]|\$))" "$1"
}
printf 'export AR_SESSION\n' > "$TMP/bare.sh"
check "scan: a bare export leaves the inherited value" "$(named "$TMP/bare.sh" AR_SESSION && echo named || echo unnamed)" "unnamed"
printf 'export X=1 AR_SESSION=t\n' > "$TMP/set.sh"
check "scan: an export that assigns names the variable" "$(named "$TMP/set.sh" AR_SESSION && echo named || echo unnamed)" "named"
printf 'unset X AR_SESSION\n' > "$TMP/unset.sh"
check "scan: an unset names the variable" "$(named "$TMP/unset.sh" AR_SESSION && echo named || echo unnamed)" "named"
found="" unnamed=""
for suite in "$HERE"/*.sh; do
  lines=$(grep -E "$runs|$sources" "$suite") || continue
  found="$found $(basename "$suite")"
  named "$suite" AR_SESSION && named "$suite" CLAUDE_CODE_SESSION_ID && continue
  # Or every such line passes both on its command line.
  [ -n "$(grep -v 'AR_SESSION=' <<<"$lines"; grep -v 'CLAUDE_CODE_SESSION_ID=' <<<"$lines")" ] || continue
  unnamed="$unnamed $(basename "$suite")"
done
check "scan: this suite is found" "$(case "$found " in *" auto-run.test.sh "*) echo found ;; *) echo missed ;; esac)" "found"
check "every suite that runs the run-control scripts sets or unsets both session variables" "${unnamed# }" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
