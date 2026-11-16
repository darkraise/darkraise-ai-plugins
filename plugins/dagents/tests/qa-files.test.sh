#!/usr/bin/env bash
# scripts/qa-files: QA's timeout cleanup touches only the paths QA listed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QA="$HERE/../scripts/qa-files"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP="$(mktemp -d)"
# git.exe under MSYS_NO_PATHCONV cannot open the shell's /tmp form.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
git init -q "$TMP/repo" && cd "$TMP/repo" || exit 1
printf '.dagents/\n' > .gitignore
printf 'one\n' > kept.txt; printf 'one\n' > qa-edit.txt; printf 'one\n' > human.txt
git add -A && git commit -qm base
WS="$TMP/repo/.dagents/sdd/p"; mkdir -p "$WS"
printf 'pre-existing\n' > dirty-before.txt

bash "$QA" begin "$WS"; rc=$?
check "begin: exit 0, manifest empty" "$rc:$(wc -c < "$WS/qa-touched.txt" | tr -d ' ')" "0:0"
# QA's work, listed; the human's work, not listed.
printf 'tests/a.acceptance.sh\nqa-edit.txt\ntests/dir/b.sh\n' >> "$WS/qa-touched.txt"
mkdir -p tests/dir && printf 'x\n' > tests/a.acceptance.sh && printf 'x\n' > tests/dir/b.sh
printf 'two\n' >> qa-edit.txt
printf 'two\n' >> human.txt
printf 'mine\n' > 'human new.txt'
out=$(bash "$QA" clean "$WS"); rc=$?
check "clean: exit 0" "$rc" "0"
check "clean: a listed new file is deleted" "$([ -e tests/a.acceptance.sh ] && echo kept || echo gone)" "gone"
check "clean: an emptied directory goes too" "$([ -e tests/dir ] && echo kept || echo gone)" "gone"
check "clean: a listed tracked edit is restored" "$(cat qa-edit.txt)" "one"
check "clean: an unlisted human edit keeps its content" "$(cat human.txt)" $'one\ntwo'
check "clean: an unlisted new file stays" "$(cat 'human new.txt')" "mine"
check "clean: a path dirty before QA stays" "$(cat dirty-before.txt)" "pre-existing"
check "clean: names what it left" "$(grep -c '^qa-files: left human.txt$' <<<"$out") $(grep -c '^qa-files: left human new.txt$' <<<"$out")" "1 1"
check "clean: names what it removed" "$(grep -c '^qa-files: removed ' <<<"$out")" "3"

# A path the auto run carried in is never cleaned, even when QA listed it.
bash "$QA" begin "$WS"
printf '{"active":true,"session":"s-qa","carried":["carried.txt"]}\n' > "$TMP/repo/.dagents/sdd/auto-run.json"
printf 'carried.txt\n' >> "$WS/qa-touched.txt"; printf 'mine\n' > carried.txt
out=$(CLAUDE_CODE_SESSION_ID=s-qa bash "$QA" clean "$WS")
check "clean: a carried path stays though QA listed it" "$(cat carried.txt):$(grep -c '^qa-files: left carried.txt$' <<<"$out")" "mine:1"
rm -f "$TMP/repo/.dagents/sdd/auto-run.json"

bash "$QA" begin "$WS"
check "a re-dispatch starts with an empty manifest" "$(wc -c < "$WS/qa-touched.txt" | tr -d ' ')" "0"
rm -f "$WS/qa-touched.txt"; printf 'z\n' > z.txt
out=$(bash "$QA" clean "$WS")
check "no manifest: nothing is cleaned" "$(cat z.txt):$(grep -c '^qa-files: left z.txt$' <<<"$out")" "z:1"
rm -f "$WS/qa-status-before.txt"
bash "$QA" clean "$WS" >/dev/null 2>&1; rc=$?
check "no snapshot: exit 2" "$rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
