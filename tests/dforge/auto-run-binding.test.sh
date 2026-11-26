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

jq '.rebind = true' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
ar --session s-b2 rebind --to s-b2 >/dev/null 2>&1
check "binding: rebind writes the new session's" "$(bfield s-b2 primary)|$(jq -r .session "$STATE")" "$REPO|s-b2"

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
setf '.pending = null'

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

mkdir -p "$REPO/docs"
printf '# P\n\n### Task 1: One\n' > "$REPO/docs/wplan.md"
git -C "$REPO" add docs/wplan.md && git -C "$REPO" commit -qm wplan
git -C "$REPO" worktree add -q -b side "$TMP/side"
mkdir -p "$TMP/side/.dforge/sdd/wplan"
printf '# SDD ledger — plan: docs/wplan.md\n' > "$TMP/side/.dforge/sdd/wplan/progress.md"
ar --session s-x attach --plan docs/wplan.md
jq -n --arg c "$A" '{cwd: $c}' > "$REC"
check "cd-prefix: a worktree run names the ledger's worktree" "$(a --session s-x cd-prefix)" "cd '$TMP/side' && "
rm -f "$REC"

# --- resolver: the working directory's run, and the commands that act on it ---
ar --session s-x stop >/dev/null 2>&1
cp "$STATE" "$TMP/b.before"
a --session s-x start --spec docs/a-spec.md >/dev/null 2>&1
check "resolver: start ignores a binding to a finished run (A49)" \
  "$(jq -r .session "$ASTATE" 2>/dev/null)|$(cmp -s "$STATE" "$TMP/b.before" && echo same)" "s-x|same"
jq -n --arg p "$REPO" '{primary: $p, nonce: "n", at: 0}' > "$RUN/s-x.json"
check "resolver: a local run of the caller wins" "$(a --session s-x status | head -n 1 | grep -c 'spec docs/a-spec.md')" "1"

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
