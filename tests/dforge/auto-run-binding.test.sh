#!/usr/bin/env bash
# A run's session binding names the primary checkout that holds its state, so
# the run follows its session out of the directory it started in.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR="$HERE/../../plugins/dforge/scripts/auto-run"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <text> <needle>
  case $2 in *"$3"*) check "$1" yes yes ;; *) check "$1" "$2" "contains: $3" ;; esac
}

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m -l "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
. "$HERE/fixtures/cockpit-ack.sh"
cockpit_ack_start "$HOME"
unset DFORGE_BIND_WAIT DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
STATE="$REPO/.dforge/sdd/auto-run.json"
SPEC=docs/dforge/specs/2026-11-25-widget-design.md
RUN="$HOME/.claude/dforge/sessions/run"
beat() { # beat <session>: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
}
ar() {
  [ "${1:-}" != --session ] || beat "$2"
  (cd "$REPO" && bash "$AR" "$@")
}
bfield() { jq -r --arg f "$2" '.[$f] | tostring' "$RUN/$1.json" 2>/dev/null; }

# --- binding ---
ar --session s-b1 start --spec "$SPEC" --force >/dev/null 2>&1
check "binding: start writes it" \
  "$(bfield s-b1 primary)|$(bfield s-b1 nonce | grep -c .)|$(jq -r '.at | type' "$RUN/s-b1.json" 2>/dev/null)" "$REPO|1|number"
n1=$(bfield s-b1 nonce)
ar --session s-b1 start --spec "$SPEC" --force >/dev/null 2>&1
n2=$(bfield s-b1 nonce)
check "binding: a second start writes a fresh nonce" "$([ -n "$n1" ] && [ "$n1" != "$n2" ] && echo differ)" "differ"

ar --session s-b3 start --spec "$SPEC" >/dev/null 2>&1; status=$?
check "binding: a refused start leaves it" "$status|$([ -e "$RUN/s-b3.json" ] && echo present || echo absent)" "4|absent"

# The command rewrote the binding (a newer write of the same session's): the
# rollback leaves it.
newer() { jq -n --arg p "$REPO" '{primary: $p, nonce: "newer", at: 0}' > "$RUN/s-b9.json"; return 1; }
rc=$( cd "$REPO" && . "$HERE/../../plugins/dforge/scripts/lib/context.sh" && . "$HERE/../../plugins/dforge/scripts/lib/auto-run.sh" && ar_binding_around s-b9 "$REPO" newer >/dev/null 2>&1; echo $? )
check "binding: a failed call keeps a newer binding" "$rc|$(bfield s-b9 nonce)" "1|newer"

jq '.rebind = true' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
ar --session s-b2 rebind --to s-b2 >/dev/null 2>&1
check "binding: rebind writes the new session's" "$(bfield s-b2 primary)|$(jq -r .session "$STATE")" "$REPO|s-b2"

# A binding that cannot be written leaves the run with the session that can still stop it.
jq '.rebind = true | .pending = null' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
HB="$TMP/home-b"
mkdir -p "$HB/.claude/dforge/sessions"
printf 'x\n' > "$HB/.claude/dforge/sessions/run"
(cd "$REPO" && HOME="$HB" bash "$AR" --session s-b9 rebind --to s-b9 >/dev/null 2>&1); status=$?
check "binding: a rebind whose binding cannot be written leaves the state" \
  "$status|$(jq -r '"\(.session) \(.rebind) \(.pending)"' "$STATE")" "1|s-b2 true null"

ar --session 'a/b:c' start --spec "$SPEC" --force >/dev/null 2>&1
check "binding: a session id is made file-safe" "$([ -f "$RUN/a-b-c.json" ] && echo yes)|$(bfield a-b-c primary)" "yes|$REPO"

# The resume of an active run is refused under the lock, after the write.
before=$(cksum < "$RUN/s-b1.json")
ar --session s-b1 resume >/dev/null 2>&1; s1=$?
ar --session s-b5 resume >/dev/null 2>&1; s5=$?
check "binding: a refused resume restores it" \
  "$s1|$(cksum < "$RUN/s-b1.json")|$s5|$([ -e "$RUN/s-b5.json" ] && echo present || echo absent)|$(ls "$RUN" | grep -c keep)" \
  "4|$before|4|absent|0"

# --- resolver: the run lives in B ($REPO), bound to s-x; A is another repository ---
A="$TMP/repo-a"
git init -q -b main "$A"
git -C "$A" commit -q --allow-empty -m init
ASTATE="$A/.dforge/sdd/auto-run.json"
a() {
  [ "${1:-}" != --session ] || beat "$2"
  (cd "$A" && bash "$AR" "$@")
}
setf() { jq "$1" "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"; }
ar --session s-x start --spec "$SPEC" --force >/dev/null 2>&1

out=$(a --session s-x status 2>&1); status=$?
check "resolver: status from another repository" "${out%%$'\n'*}|$status" "$(ar --session s-x status 2>&1 | head -n 1)|0"
setf '.pending = "compact"'
out=$(a --session s-x pending 2>&1); status=$?
check "resolver: pending from another repository" "$out|$status" "compact|0"
setf '.pending = "after-compact"'
ar --session s-x after-compact >/dev/null 2>&1; here=$?
setf '.pending = "after-compact"'
a --session s-x after-compact >/dev/null 2>&1; there=$?
check "resolver: after-compact from another repository" "$there|$(jq -r .pending "$STATE")" "$here|null"
setf '.pending = "compact"'
out=$(cd "$TMP" && bash "$AR" --session s-x pending 2>&1)
check "resolver: outside any repository" "$out" "compact"
setf '.pending = null | .rebind = true'
a --session s-x rebind --to s-y >/dev/null 2>&1; status=$?
check "resolver: rebind from another repository binds the new session to the run's primary" \
  "$status|$(bfield s-y primary)|$(jq -r .session "$STATE")" "0|$REPO|s-y"
setf '.session = "s-x" | .pending = null'

cp "$STATE" "$TMP/b.before"
err=$(a --session s-x task-complete 2>&1 >/dev/null); status=$?
check "resolver: task-complete elsewhere exits 7" \
  "$status|$err|$(cmp -s "$STATE" "$TMP/b.before" && echo same)" "7|auto-run: run this from the run's checkout: cd '$REPO' && …|same"
err=$(a --session s-x phase final 2>&1 >/dev/null); status=$?
check "resolver: phase final elsewhere exits 7" \
  "$status|$err|$(cmp -s "$STATE" "$TMP/b.before" && echo same)" "7|auto-run: run this from the run's checkout: cd '$REPO' && …|same"

# --- cd-prefix ---
REC="$HOME/.claude/dforge/sessions/by-id/s-x.json"
mkdir -p "$(dirname "$REC")"
jq -n --arg c "$A" '{cwd: $c}' > "$REC"
out1=$(a --session s-x cd-prefix); s1=$?
jq -n --arg c "$REPO" '{cwd: $c}' > "$REC"
out2=$(a --session s-x cd-prefix); s2=$?
rm -f "$REC"
out3=$(a --session s-x cd-prefix); s3=$?
check "cd-prefix: outside the starting directory" "$out1|$s1|$out2|$s2|$out3|$s3" "cd '$REPO' && |0||0||0"
# Another spelling of the same directory (an 8.3 short name under Git Bash, a
# symlink here) is still the starting directory.
if ln -s "$(dirname "$REPO")" "$TMP/alias" 2>/dev/null && [ -L "$TMP/alias" ]; then
  jq -n --arg c "$TMP/alias" '{cwd: $c}' > "$REC"
  out4=$(a --session s-x cd-prefix); s4=$?
  jq -n --arg c "$TMP/alias/$(basename "$REPO")" '{cwd: $c}' > "$REC"
  out5=$(a --session s-x cd-prefix); s5=$?
  rm -f "$REC"
  check "cd-prefix: another spelling of the starting directory needs no cd" "$out4|$s4|$out5|$s5" "|0||0"
else
  printf 'skip - cd-prefix: another spelling needs a symlink this system does not make\n'
fi

mkdir -p "$REPO/docs"
printf '# P\n\n### Task 1: One\n' > "$REPO/docs/wplan.md"
git -C "$REPO" add docs/wplan.md && git -C "$REPO" commit -qm wplan
git -C "$REPO" worktree add -q -b side "$TMP/side"
mkdir -p "$TMP/side/.dforge/sdd/wplan"
printf '# SDD ledger — plan: docs/wplan.md\n' > "$TMP/side/.dforge/sdd/wplan/progress.md"
ar --session s-x attach --plan docs/wplan.md
jq -n --arg c "$A" '{cwd: $c}' > "$REC"
check "cd-prefix: a worktree run names the ledger's worktree" "$(a --session s-x cd-prefix)" "cd '$TMP/side' && "
out1=$(a --session s-x cd-prefix --dir "$TMP/o'k"); s1=$?
out2=$(a --session s-x cd-prefix --dir "$A/.worktrees/x"); s2=$?
check "cd-prefix: --dir names the given directory" "$out1|$s1|$out2|$s2" "cd '$TMP/o'\''k' && |0||0"
rm -f "$REC"

# --- resolver: the working directory's run, and the commands that act on it ---
ar --session s-x stop >/dev/null 2>&1
cp "$STATE" "$TMP/b.before"
a --session s-x start --spec docs/a-spec.md >/dev/null 2>&1
check "resolver: start ignores a binding to a finished run (A49)" \
  "$(jq -r .session "$ASTATE" 2>/dev/null)|$(cmp -s "$STATE" "$TMP/b.before" && echo same)" "s-x|same"
jq -n --arg p "$REPO" '{primary: $p, nonce: "n", at: 0}' > "$RUN/s-x.json"
check "resolver: a local run of the caller wins" "$(a --session s-x status | head -n 1 | grep -c 'spec docs/a-spec.md')" "1"

# A run of the caller's that ended here must not hide the active one its binding names.
a --session s-x stop >/dev/null 2>&1
setf '.active = true | .stopped = null | .pending = "compact"'
out=$(a --session s-x pending 2>&1); status=$?
setf '.active = false'
out2=$(a --session s-x pending 2>&1); s2=$?
check "resolver: an active bound run goes before an ended local run" "$out|$status|$s2" "compact|0|3"

a --session s-old start --spec docs/old.md --force >/dev/null 2>&1
beat s-old && printf '%s\n' "$(( $(date +%s) - 1000 ))" > "$HOME/.claude/dforge/sessions/cockpit/s-old"
ar --session s-x start --spec "$SPEC" --force >/dev/null 2>&1
cp "$STATE" "$TMP/b.before"
(cd "$A" && bash "$AR" --session s-x stop --stale >/dev/null 2>&1); s1=$?
active1=$(jq -r .active "$ASTATE")
a --session s-x resume >/dev/null 2>&1; s2=$?
check "resolver: stop --stale and resume act on this repository" \
  "$s1|$active1|$s2|$(jq -r '"\(.active) \(.session)"' "$ASTATE")|$(cmp -s "$STATE" "$TMP/b.before" && echo same)" \
  "0|false|0|true s-x|same"

# --- ack: a second HOME whose cockpit never echoes ---
H2="$TMP/home2"
mkdir -p "$H2"
RN="$TMP/repo-n"
git init -q -b main "$RN"
git -C "$RN" commit -q --allow-empty -m init
NSTATE="$RN/.dforge/sdd/auto-run.json"
mute() { # mute <session> ARGS… — from RN, in H2, with a live beat and a 1 s wait
  local s=$1 f
  shift
  f="$H2/.claude/dforge/sessions/cockpit/$s"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
  (cd "$RN" && HOME="$H2" DFORGE_BIND_WAIT=${WAIT:-1} bash "$AR" --session "$s" "$@")
}
err=$(mute s-n1 start --spec "$SPEC" 2>&1 >/dev/null); status=$?
check "ack: start without an echo exits 2 (A3)" \
  "$status|$err|$([ -e "$NSTATE" ] && echo state)|$([ -e "$H2/.claude/dforge/sessions/run/s-n1.json" ] && echo binding)" \
  "2|auto-run: the cockpit in this session does not see this run||"

(cd "$RN" && beat s-n0 && bash "$AR" --session s-n0 start --spec "$SPEC" >/dev/null 2>&1)
mkdir -p "$H2/.claude/dforge/sessions/run"
printf '{"primary":"/elsewhere","nonce":"old","at":1}\n' > "$H2/.claude/dforge/sessions/run/s-n1.json"
cp "$H2/.claude/dforge/sessions/run/s-n1.json" "$TMP/n1.before"
cp "$NSTATE" "$TMP/n.before"
mute s-n1 start --spec "$SPEC" --force >/dev/null 2>&1; status=$?
check "ack: start --force over another run changes nothing (A3)" \
  "$status|$(cmp -s "$NSTATE" "$TMP/n.before" && echo same)|$(cmp -s "$H2/.claude/dforge/sessions/run/s-n1.json" "$TMP/n1.before" && echo same)" "2|same|same"

(cd "$RN" && beat s-n0 && bash "$AR" --session s-n0 stop >/dev/null 2>&1)
cp "$NSTATE" "$TMP/n.before"
err=$(mute s-n1 resume 2>&1 >/dev/null); status=$?
check "ack: resume without an echo exits 2 (A3)" \
  "$status|$err|$(cmp -s "$NSTATE" "$TMP/n.before" && echo same)" "2|auto-run: the cockpit in this session does not see this run|same"

ar --session s-n3 start --spec "$SPEC" --force >/dev/null 2>&1; status=$?
check "ack: an echoed start succeeds" "$status|$(jq -r .session "$STATE")" "0|s-n3"

check "status: cockpit sees this run (A4)" "$(ar --session s-n3 status | sed -n 2p)" "cockpit: sees this run"
rm -f "$RUN/s-n3.seen"
s1=$(ar --session s-n3 status | sed -n 2p)
jq -c '.nonce = "other"' "$RUN/s-n3.json" > "$RUN/s-n3.seen"
check "status: cockpit does not see this run (A4)" "$s1|$(ar --session s-n3 status | sed -n 2p)" "cockpit: does not see this run|cockpit: does not see this run"

jq '.active = true | .rebind = true | .stopped = null' "$NSTATE" > "$NSTATE.tmp" && mv "$NSTATE.tmp" "$NSTATE"
t0=$(date +%s%N)
WAIT=5 mute s-n2 rebind --to s-n2 >/dev/null 2>&1; status=$?
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
check "ack: rebind does not wait (A4)" \
  "$status|$([ "$ms" -lt 2000 ] && echo quick || echo "$ms ms")|$([ -f "$H2/.claude/dforge/sessions/run/s-n2.json" ] && echo written)" "0|quick|written"

# --- log ---
LR="$TMP/repo-log"
git init -q -b main "$LR"
git -C "$LR" commit -q --allow-empty -m init
LOG="$LR/.dforge/sdd/auto-run-log.tsv"
lr() {
  [ "${1:-}" != --session ] || beat "$2"
  (cd "$LR" && bash "$AR" "$@")
}
handoff_for() { # handoff_for <session>: the handoff a clear of that session reads
  mkdir -p "$LR/.dforge/handoff"
  printf '# Handoff\n\n## Next session\n\n**Status:** s\n**Next:** n\n\nLaunch in `/work`:\n\n```\nclaude --model opus --effort high\n```\n\nPaste as the first prompt:\n\n```\nKeep designing.\n```\n<!-- next-step: kind=adhoc session=%s done=0 closed=0 subject=- at=%s -->\n' \
    "$1" "$(date +%s)" > "$LR/.dforge/handoff/stored.md"
}
lr --session s-l1 start --spec "$SPEC" >/dev/null 2>&1
lr --session s-l1 phase plan >/dev/null 2>&1
lr --session s-l1 compacted >/dev/null 2>&1
handoff_for s-l1
lr --session s-l1 clear --phase >/dev/null 2>&1
lr --session s-l1 stop --reason "disk full" >/dev/null 2>&1
lr --session s-l2 start --spec "$SPEC" --force >/dev/null 2>&1
out=$(lr log); status=$?
check "log: a stopped run survives the next start (A6)" \
  "$status|$(cut -f2 <<<"$out" | head -n 8 | tr '\n' ' ')|$(awk -F'\t' '$2 == "stop" { print $5 }' <<<"$out")|$(cut -f2 <<<"$out" | grep -cx start)" \
  "0|start bind phase compacted clear stop start bind |disk full|2"
check "log: rows have five columns" \
  "$(awk -F'\t' 'NF != 5 || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:][0-9:][0-9:][0-9:][0-9:][0-9:][0-9:][0-9:]Z$/' <<<"$out" | wc -l | tr -d ' ')|$(awk -F'\t' '$2 == "phase" || $2 == "compacted" || $2 == "start" { printf "%s %s %s;", $2, $3, $4 }' <<<"$out")" \
  "0|start s-l1 spec;phase s-l1 plan;compacted s-l1 plan;start s-l2 spec;"

lr --session s-l2 stop --reason $'a\tb\nc' >/dev/null 2>&1
check "log: a reason with a tab stays one row" "$(tail -n 1 "$LOG" | cut -f2,5)" $'stop\ta b c'

lr --session s-l2 resume >/dev/null 2>&1
lr --session s-l2 total holds >/dev/null 2>&1
lr --session s-l2 stalled >/dev/null 2>&1
handoff_for s-l2
lr --session s-l2 clear >/dev/null 2>&1
lr --session s-l3 rebind --to s-l3 >/dev/null 2>&1
check "log: a hold, a stall, a rebind and a resume are rows" \
  "$(cut -f2 "$LOG" | tail -n 6 | tr '\n' ' ')|$(awk -F'\t' '$2 == "rebind" { print $5 }' "$LOG")" \
  "resume bind hold stalled clear rebind |s-l3"

mv "$LOG" "$TMP/log.aside" && mkdir "$LOG"
lr --session s-l3 phase plan >/dev/null 2>&1; status=$?
rmdir "$LOG" && mv "$TMP/log.aside" "$LOG"
check "log: an unwritable log never fails the command" "$status" "0"

NL="$TMP/repo-nolog"
git init -q -b main "$NL"
git -C "$NL" commit -q --allow-empty -m init
out=$(cd "$NL" && bash "$AR" log 2>/dev/null); status=$?
check "log: no log exits 3" "$status|$out" "3|"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
