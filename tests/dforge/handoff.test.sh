#!/usr/bin/env bash
# scripts/handoff: one repository-wide claim per handoff key, taken over only
# from a gone session, and a listing of every checkout's handoffs with their
# claim states.
set -uo pipefail
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID AR_SESSION

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H="$HERE/../../plugins/dforge/scripts/handoff"
AR="$HERE/../../plugins/dforge/scripts/auto-run"
. "$HERE/../../plugins/dforge/scripts/lib/session-live.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
TOP=$(git -C "$REPO" rev-parse --show-toplevel)
git -C "$REPO" worktree add -q -b wt "$TMP/wt"
WT=$(git -C "$TMP/wt" rev-parse --show-toplevel)
HD="$TOP/.dforge/handoff"
CLAIMS="$HD/claims"
mkdir -p "$HD" "$WT/.dforge/handoff"

S2=S2000000-0000-0000-0000-000000000002
S3=S3000000-0000-0000-0000-000000000003
beat() { # beat <session> [age in seconds]: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(( $(date +%s) - ${2:-0} ))" > "$f"
}
as() { local sid=$1; shift; (cd "$REPO" && CLAUDE_CODE_SESSION_ID=$sid bash "$H" "$@"); } # as <session> <args…>
handoff_md() { printf '# Handoff\n<!-- next-step: kind=%s key=%s session=- done=0 closed=0 subject=x at=1 -->\n' "$2" "$(basename "$1" .md)" > "$1"; }

# claim_unclaimed_then_again
handoff_md "$HD/P.md" plan
beat S2
out=$(as S2 claim "$HD/P.md"); rc=$?
check "claim_unclaimed_then_again: exit 0" "$rc" "0"
check "claim_unclaimed_then_again: stdout" "$out" "claimed P"
check "claim_unclaimed_then_again: the claim names the session" "$(sed -n 1p "$CLAIMS/P")" "session=S2"
check "claim_unclaimed_then_again: the claim has a time" "$(grep -c '^at=[0-9][0-9]*$' "$CLAIMS/P")" "1"
before=$(cat "$CLAIMS/P")
out=$(as S2 claim "$HD/P.md"); rc=$?
check "claim_unclaimed_then_again: again, exit 0" "$rc" "0"
check "claim_unclaimed_then_again: again, unchanged" "$(cat "$CLAIMS/P")" "$before"
check "the state directory ignores itself" "$(cat "$TOP/.dforge/.gitignore")" "*"

# claim_held_by_live_session
handoff_md "$HD/L.md" plan
mkdir -p "$CLAIMS"
printf 'session=%s\nat=%s\n' "$S2" "$(( $(date +%s) - 120 ))" > "$CLAIMS/L"
beat "$S2"
cp "$CLAIMS/L" "$TMP/L.before"
out=$(as "$S3" claim "$HD/L.md"); rc=$?
check "claim_held_by_live_session: exit 3" "$rc" "3"
check "claim_held_by_live_session: stdout" "$out" "held by S2000000 (live, claimed 2m ago)"
check "claim_held_by_live_session: the claim is byte-identical" "$(cmp -s "$CLAIMS/L" "$TMP/L.before" && echo same)" "same"

# claim_takeover_of_gone_session
beat "$S2" $(( AR_BEAT_SECONDS + 60 ))
out=$(as "$S3" claim "$HD/L.md"); rc=$?
check "claim_takeover_of_gone_session: exit 0" "$rc" "0"
check "claim_takeover_of_gone_session: stdout" "${out%%(*}" "took over the claim of S2000000 "
check "claim_takeover_of_gone_session: the reason" "$out" "took over the claim of S2000000 (gone: beat 4m old)"
check "claim_takeover_of_gone_session: the new session" "$(sed -n 1p "$CLAIMS/L")" "session=$S3"
check "claim_takeover_of_gone_session: the previous session" "$(grep -c "^previous=$S2 beat 4m old\$" "$CLAIMS/L")" "1"

# claim_edges
out=$(as S2 claim "$HD/missing.md"); rc=$?
check "claim_edges: a missing file exits 0" "$rc" "0"
check "claim_edges: a missing file says so" "$out" "no handoff file at $HD/missing.md"
check "claim_edges: a missing file is not claimed" "$([ -e "$CLAIMS/missing" ] && echo claimed || echo none)" "none"
printf 'x\n' > "$HD/a b.md"
out=$(as S2 claim "$HD/a b.md" 2>&1); rc=$?
check "claim_edges: an invalid key exits 2" "$rc:$out" "2:handoff: invalid key a b"
handoff_md "$HD/N.md" adhoc
out=$(cd "$REPO" && bash "$H" claim "$HD/N.md"); rc=$?
check "claim_edges: no session id exits 0" "$rc" "0"
check "claim_edges: no session id says so" "$out" "claims are Claude Code only; not claimed"
check "claim_edges: no session id writes no claim" "$([ -e "$CLAIMS/N" ] && echo claimed || echo none)" "none"
out=$(as S2 claim 2>&1); rc=$?
check "claim_edges: no file is a usage error" "$rc" "2"
out=$(cd "$REPO" && bash "$H" release x 2>&1); rc=$?
check "claim_edges: an unknown command is a usage error" "$rc" "2"

# claim_is_repository_wide
handoff_md "$WT/.dforge/handoff/W.md" plan
beat "$S2"
out=$(cd "$WT" && CLAUDE_CODE_SESSION_ID=$S2 bash "$H" claim "$WT/.dforge/handoff/W.md"); rc=$?
check "claim_is_repository_wide: claimed from the worktree" "$rc:$out" "0:claimed W"
check "claim_is_repository_wide: the claim is the primary's" "$(sed -n 1p "$CLAIMS/W")" "session=$S2"
handoff_md "$HD/W.md" plan
out=$(as "$S3" claim "$HD/W.md"); rc=$?
check "claim_is_repository_wide: the same key in the primary is held" "$rc" "3"

# a held claim stops this session's auto run (C16)
SPEC=docs/dforge/specs/2026-11-20-widget-design.md
beat "$S3"
(cd "$REPO" && bash "$AR" --session "$S3" start --spec "$SPEC" --isolation in-place > /dev/null 2>&1)
check "C16: the run is active before the claim" "$(cd "$REPO" && bash "$AR" --session "$S3" status > /dev/null 2>&1; echo $?)" "0"
out=$(as "$S3" claim "$HD/W.md"); rc=$?
check "C16: a held claim still exits 3" "$rc" "3"
check "C16: the run is stopped" "$(jq -r '.active' "$TOP/.dforge/sdd/auto-run.json")" "false"
check "C16: with the claim as its reason" "$(jq -r '.stopped // empty' "$TOP/.dforge/sdd/auto-run.json")" "handoff W is held by $(printf '%s' "$S2" | cut -c1-8)"
# A stop that cannot take the run's lock is said, not swallowed.
(cd "$REPO" && bash "$AR" --session "$S3" start --spec "$SPEC" --isolation in-place --force > /dev/null 2>&1)
sleep 30 & holder=$!
LOCKD="$TOP/.dforge/sdd/auto-run.json.lockd"
mkdir "$LOCKD" && printf '%s\n' "$holder" > "$LOCKD/pid" && uname -n > "$LOCKD/host"
out=$(DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=5 as "$S3" claim "$HD/W.md" 2>&1); rc=$?
kill "$holder"; wait "$holder" 2>/dev/null; rm -f "$LOCKD/pid" "$LOCKD/host"; rmdir "$LOCKD"
check "C16: with the run's lock held, the claim still exits 3" "$rc" "3"
check "C16: and says the stop failed" "$(grep -c '^handoff: auto-run stop failed (status [0-9]*); the run is still active$' <<<"$out")" "1"
check "C16: the run is still active" "$(jq -r '.active' "$TOP/.dforge/sdd/auto-run.json")" "true"

# list_reports_claim_states
rm -rf "$HD" "$WT/.dforge/handoff"
mkdir -p "$CLAIMS" "$WT/.dforge/handoff"
handoff_md "$HD/U.md" plan
handoff_md "$HD/V.md" draft
printf '# no marker\n' > "$HD/X.md"
printf 'session=%s\nat=1\n' "$S2" > "$CLAIMS/V"
printf 'session=%s\nat=1\n' "$S3" > "$CLAIMS/X"
beat "$S2"
beat "$S3" $(( AR_BEAT_SECONDS + 60 ))
out=$(cd "$REPO" && bash "$H" list)
check "list_reports_claim_states: three lines" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "3"
check "list_reports_claim_states: unclaimed" "$(printf '%s\n' "$out" | awk -F'\t' '$2 == "U" { print $1 "|" $3 "|" $5 }')" "$HD/U.md|plan|unclaimed"
check "list_reports_claim_states: live" "$(printf '%s\n' "$out" | awk -F'\t' '$2 == "V" { print $3 "|" $5 }')" "draft|claimed S2000000 live"
check "list_reports_claim_states: gone, no marker" "$(printf '%s\n' "$out" | awk -F'\t' '$2 == "X" { print $3 "|" $5 }')" "none|claimed S3000000 gone"
check "list_reports_claim_states: the age is seconds" "$(printf '%s\n' "$out" | awk -F'\t' '$2 == "U" && $4 ~ /^[0-9]+$/ { print "n" }')" "n"
handoff_md "$WT/.dforge/handoff/Y.md" adhoc
check "list: a worktree's handoff is listed" "$(cd "$REPO" && bash "$H" list | awk -F'\t' '$2 == "Y" { print $1 }')" "$WT/.dforge/handoff/Y.md"
check "list --checkout: the primary omits the worktree's" "$(cd "$WT" && bash "$H" list --checkout "$REPO" | grep -c 'Y.md')" "0"
check "list --checkout: the primary lists its own" "$(cd "$WT" && bash "$H" list --checkout "$REPO" | wc -l | tr -d ' ')" "3"
check "list --checkout: from the worktree, its own only" "$(cd "$WT" && bash "$H" list --checkout | cut -f2)" "Y"

# progress in darkmem: the mirror's handoffs are the primary's
. "$HERE/fixtures/darkmem-stores.sh"
MIRROR=$(stores_home "$HOME" "$REPO" repo local darkmem)
handoff_md "$MIRROR/work/handoff/M.md" plan
check "darkmem: list names the mirror's" "$(cd "$WT" && bash "$H" list | awk -F'\t' '$2 == "M" { print $1 }')" "$MIRROR/work/handoff/M.md"
check "darkmem: list --checkout of the primary names the mirror's" "$(cd "$WT" && bash "$H" list --checkout "$REPO" | grep -c "M.md")" "1"
check "darkmem: list --checkout of a worktree does not" "$(cd "$WT" && bash "$H" list --checkout | grep -c "M.md")" "0"
out=$(cd "$WT" && CLAUDE_CODE_SESSION_ID=$S2 bash "$H" claim "$MIRROR/work/handoff/M.md"); rc=$?
check "darkmem: a mirror handoff is claimed in the primary" "$rc:$(sed -n 1p "$CLAIMS/M")" "0:session=$S2"
git init -q "$HOME"
handoff_md "$MIRROR/work/handoff/G.md" plan
out=$(cd "$WT" && CLAUDE_CODE_SESSION_ID=$S2 bash "$H" claim "$MIRROR/work/handoff/G.md"); rc=$?
check "darkmem: a HOME kept in git does not take the mirror's claim" "$rc:$(sed -n 1p "$CLAIMS/G" 2>/dev/null)" "0:session=$S2"
check "darkmem: no claim inside the HOME repository" "$([ -e "$HOME/.dforge/handoff/claims/G" ] && echo there || echo none)" "none"
check "darkmem: list sees that claim" "$(cd "$WT" && bash "$H" list | awk -F'\t' '$2 == "G" { print $5 }')" "claimed S2000000 live"
rm -rf "$HOME/.git"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
