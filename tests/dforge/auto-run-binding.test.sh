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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
