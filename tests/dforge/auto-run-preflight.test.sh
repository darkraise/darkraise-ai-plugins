#!/usr/bin/env bash
# auto-run preflight names what would stop an unattended run (disk space, a
# refused git write or scratch worktree) and how each review family stands,
# before the spec review, while the owner is still there to fix it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR="$HERE/../../plugins/dforge/scripts/auto-run"

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
unset DFORGE_PREFLIGHT_FREE DFORGE_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
ROOT=$(git -C "$REPO" rev-parse --show-toplevel | tr -d '\r')
pf() { (cd "$REPO" && bash "$AR" preflight "$@" 2>"$TMP/err"); }
starts() { # starts <text> <prefix>: how many lines of text start with prefix
  local n=0 l
  while IFS= read -r l; do case $l in "$2"*) n=$((n + 1)) ;; esac; done <<<"$1"
  printf '%s' "$n"
}

# --- ok ---
out=$(DFORGE_PREFLIGHT_FREE=0 pf --isolation in-place); status=$?
review=$(sed -n '2,$p' <<<"$out" | sed -E 's/^(preflight: review [a-z]+: usable=false reason=setting ).* — setting off$/\1… — setting off/')
check "ok: nothing found" "$status|$(sed -n 1p <<<"$out")|$review" \
  "0|preflight: ok|preflight: review agy: usable=false reason=setting … — setting off
preflight: review codex: usable=false reason=setting … — setting off"
check "git: the probe leaves no ref" "$(git -C "$REPO" show-ref refs/dforge/preflight)|$([ -e "$REPO/.git/refs/dforge" ] && echo left || echo gone)" "|gone"

# --- space ---
out=$(DFORGE_PREFLIGHT_FREE=101 pf --isolation in-place); status=$?
check "space: below the threshold" \
  "$status|$(grep -cE "^preflight: free space [0-9]+% on .+ \(below 101%\)$" <<<"$out")|$(grep -cE "^preflight: free space [0-9]+% on $ROOT \(below 101%\)$" <<<"$out")|$(grep -c '^preflight: ok$' <<<"$out")" \
  "0|2|1|0"

# --- git ---
mkdir -p "$REPO/.git/refs"
printf 'x\n' > "$REPO/.git/refs/dforge"
out=$(DFORGE_PREFLIGHT_FREE=0 pf --isolation in-place); status=$?
rm -f "$REPO/.git/refs/dforge"
check "git: a refused write" "$status|$(starts "$out" "preflight: git write refused in $ROOT: ")|$(grep -c '^preflight: ok$' <<<"$out")" "0|1|0"

# --- worktree ---
printf 'x\n' > "$REPO/.worktrees"
out=$(DFORGE_PREFLIGHT_FREE=0 pf --isolation worktree); status=$?
inplace=$(DFORGE_PREFLIGHT_FREE=0 pf --isolation in-place)
rm -f "$REPO/.worktrees"
check "worktree: a refused scratch worktree" \
  "$status|$(starts "$out" "preflight: scratch worktree refused in $ROOT/.worktrees: ")|$(grep -c 'scratch worktree' <<<"$inplace")" "0|1|0"

printf 'x\n' > "$REPO/worktrees"
out=$(DFORGE_PREFLIGHT_FREE=0 pf --isolation worktree)
rm -f "$REPO/worktrees"
check "worktree: an existing worktrees name is used" \
  "$(starts "$out" "preflight: scratch worktree refused in $ROOT/worktrees: ")|$([ -e "$REPO/.worktrees" ] && echo made || echo none)" "1|none"

out=$(DFORGE_PREFLIGHT_FREE=0 pf --isolation worktree); status=$?
check "worktree: the probe leaves no worktree" \
  "$status|$(sed -n 1p <<<"$out")|$(git -C "$REPO" worktree list | wc -l | tr -d ' ')|$([ -e "$REPO/.worktrees" ] && echo left || echo gone)" \
  "0|preflight: ok|1|gone"

# --- usage ---
pf --isolation nowhere >/dev/null; s1=$?
e1=$(cat "$TMP/err")
pf >/dev/null; s2=$?
e2=$(cat "$TMP/err")
check "usage: a bad isolation exits 2" "$s1|$e1|$s2|$e2" \
  "2|auto-run: --isolation must be worktree or in-place|2|auto-run: --isolation must be worktree or in-place"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
