#!/usr/bin/env bash
# run-agy-review.sh is the agy reviewer. Every case runs the stub agy behind
# a stub gate line, in a throwaway repository and session directory.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
RUN="$P/scripts/run-agy-review.sh"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" DR_AGY_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=s1
export DR_AGY_POLICY="$TMP/policy.json" STUB_AGY_ARGS_LOG="$TMP/args"
mkdir -p "$HOME" "$TMP/work"
cp "$P/reference/agy-policy.json" "$DR_AGY_POLICY"
printf '# r\n' > "$TMP/prompt.md"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
git -C "$TMP/work" init -q && git -C "$TMP/work" config user.name t && git -C "$TMP/work" config user.email t@t
printf 'base\n' > "$TMP/work/tracked.txt"; git -C "$TMP/work" add tracked.txt; git -C "$TMP/work" commit -qm base
export PATH="$P/tests/fixtures/stub-agy:$PATH"
# A stub gate line, not the real gate: the real gate's probe spawns the stub
# from Node, which Windows Git Bash cannot do.
GATE_ON='agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=cache'
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GATE_LINE:-%s}"\n' "$GATE_ON" > "$TMP/gate"; chmod +x "$TMP/gate"
run() { # run <args...>; sets out, rc
  rm -f "$TMP/args"
  out=$(cd "$TMP/work" && AGY_REVIEW_GRACE=5 AGY_REVIEW_GATE="$TMP/gate" bash "$RUN" --cwd "$TMP/work" --out "$TMP/out.json" "$@" 2>"$TMP/err"); rc=$?
}
args() { tr '\n' ' ' < "$TMP/args" 2>/dev/null; }
field() { jq -r ".$1 | tostring" "$DR_AGY_SESSION_DIR/s1.json" 2>/dev/null | tr -d '\r'; }
near() { # near <epoch> <seconds from now>: the epoch is that far ahead, within a minute
  local now; now=$(date -u +%s)
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge $((now + $2 - 60)) ] && [ "$1" -le $((now + $2)) ] && echo near || echo "$1"
}

STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
check "light review answers OK" "$out" "agy-judge gemini-4-argon/high status=OK exit=0 out=$TMP/out.json evidence=none"
check "light review exits 0" "$rc" "0"
has "the reviewer runs in plan mode" "$(args)" "--mode plan"
has "the task schema is enforced" "$(args)" "codex-review-schema.json"
has "the prompt directory is added" "$(args)" "--add-dir"
lacks "permissions are never skipped" "$(args)" "--dangerously-skip-permissions"
check "the list lands in --out" "$(jq -r .spec_verdict "$TMP/out.json")" "compliant"
STUB_AGY_SCHEMA_COPY="$TMP/seen-schema.json" STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
check "agy receives no integer enum" "$(jq '[.. | objects | select(.type == "integer" and has("enum"))] | length' < "$TMP/seen-schema.json")" "0"
check "the scores keep their bounds" "$(jq -c '.properties.spec | [.minimum, .maximum]' < "$TMP/seen-schema.json")" "[1,20]"
check "the shipped schema keeps its enums" "$(jq '.properties.spec.enum | length' < "$P/criteria/codex-review-schema.json")" "20"
STUB_AGY_SCORE=21 STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
has "a score outside the shipped enum is a schema failure" "$out" "reason=schema"
STUB_AGY_VERDICT=PASS STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
has "a verdict outside the shipped enum is a schema failure" "$out" "reason=schema"

STUB_AGY_MODE=review run --kind task --tier heavy --prompt "$TMP/prompt.md"
check "heavy review prefers agy Opus" "$out" "agy-judge claude-opus-5-5/high status=OK exit=0 out=$TMP/out.json evidence=none"
STUB_AGY_REFUSE_MODEL=claude-opus-5-5 STUB_AGY_MODE=review run --kind task --tier heavy --prompt "$TMP/prompt.md"
has "a refused Opus falls back to Argon" "$out" "agy-judge gemini-4-argon/high status=FALLBACK"
STUB_AGY_REFUSE_MODEL=gemini-4-argon STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
has "the light tier never falls back" "$out" "status=FAILED"
has "a refusal names its reason" "$out" "reason=refused"

reset_work() {
  git -C "$TMP/work" stash clear; git -C "$TMP/work" checkout -q -- .; git -C "$TMP/work" clean -qfd
  rm -f "$(git -C "$TMP/work" rev-parse --path-format=absolute --git-path hooks)/pre-commit"
  git -C "$TMP/work" config --unset dforge.stub
}
for side in write commit stash modify delete hook config; do
  reset_work
  STUB_AGY_WRITE=$side.txt STUB_AGY_SIDE=$side STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
  has "a reviewer that does $side fails" "$out" "status=FAILED"
  has "a $side run is evidence=wrote" "$out" "evidence=wrote reason=wrote"
  check "a $side run names what changed" "$([ -s "$TMP/out.json.wrote" ] && echo named || echo none)" "named"
  case $side in
    commit) check "a commit names HEAD" "$(grep -cx HEAD "$TMP/out.json.wrote")" "1" ;;
    stash) check "a stash names the stash list" "$(grep -cx stash "$TMP/out.json.wrote")" "1" ;;
    modify|delete) check "a $side run names the tracked file" "$(grep -cx tracked.txt "$TMP/out.json.wrote")" "1" ;;
    hook) check "a planted hook is named" "$(grep -c '/hooks/pre-commit$' "$TMP/out.json.wrote")" "1" ;;
    config) check "a git config change is named" "$(grep -c '/config$' "$TMP/out.json.wrote")" "1" ;;
  esac
done
reset_work

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_FINDING='{"severity":"Minor","where":"a","what":"quota wording"}' STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
has "a clean answer mentioning quota is a list" "$out" "status=OK"
check "a clean answer marks nothing" "$([ -f "$DR_AGY_SESSION_DIR/s1.json" ] && echo marked || echo none)" "none"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=stderr-quota run --kind task --tier light --prompt "$TMP/prompt.md"
has "a stderr-only quota fails the run" "$out" "reason=quota-stderr"
check "a stderr-only quota marks nothing" "$([ -f "$DR_AGY_SESSION_DIR/s1.json" ] && echo marked || echo none)" "none"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=error STUB_AGY_ERROR='request 14290 failed' run --kind task --tier light --prompt "$TMP/prompt.md"
has "429 inside a number is no quota" "$out" "reason=error"

STUB_AGY_MODE=print-timeout run --kind task --tier light --prompt "$TMP/prompt.md"
has "a print timeout is TIMEOUT" "$out" "status=TIMEOUT"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota for claude. Resets in 2h' run --kind task --tier heavy --prompt "$TMP/prompt.md"
has "a Claude quota fails the Opus run" "$out" "agy-judge claude-opus-5-5/high status=FAILED"
check "a Claude quota marks the Claude row" "$(field fallback.usable)" "false"
check "a Claude quota leaves agy usable" "$([ "$(field usable)" = false ] && echo off || echo on)" "on"
check "a Claude quota's reset is two hours ahead" "$(near "$(field fallback.resets_at_epoch)" 7200)" "near"
GATE_LINE="${GATE_ON/claude=on/claude=off}" STUB_AGY_MODE=review run --kind task --tier heavy --prompt "$TMP/prompt.md"
check "the next heavy review runs Argon directly" "$out" "agy-judge gemini-4-argon/high status=OK exit=0 out=$TMP/out.json evidence=claude-off"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota' run --kind task --tier light --prompt "$TMP/prompt.md"
check "a Gemini quota turns agy off" "$(field usable)/$(field reason)" "false/quota"
rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota. Resets in 1d2h3m4s' run --kind task --tier light --prompt "$TMP/prompt.md"
check "a Gemini quota's reset counts days, hours, minutes and seconds" "$(near "$(field resets_at_epoch)" 93784)" "near"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=plan-review run --kind plan --prompt "$TMP/prompt.md"
has "a plan review uses the plan schema" "$(args)" "codex-plan-review-schema.json"
has "a plan review takes the heavy row" "$out" "claude-opus-5-5/high status=OK"
printf 'final\n' > "$TMP/work/final.txt"; git -C "$TMP/work" add final.txt; git -C "$TMP/work" commit -qm final
STUB_AGY_MODE=final-review run --kind final --base HEAD~1
has "a final review uses its schema" "$(args)" "agy-final-review-schema.json"
check "a final review writes its text" "$(cat "$TMP/out.json")" "No findings."
has "the final prompt carries the branch diff" "$(cat "$TMP/out.json.prompt")" "+final"
lacks "the final prompt never sends agy to git" "$(cat "$TMP/out.json.prompt")" "Review the branch diff from"
STUB_AGY_MODE=final-review run --kind final --base nosuchsha
has "a final review of an unknown base fails" "$out" "status=FAILED"
has "an unknown base names error" "$out" "reason=error"
check "an unknown base exits 1" "$rc" "1"
check "an unknown base leaves no list" "$([ -e "$TMP/out.json" ] && echo list || echo none)" "none"
for empty in '""' '" \n "' null; do
  STUB_AGY_REVIEW_JSON=$empty STUB_AGY_MODE=final-review run --kind final --base HEAD~1
  has "a final review of $empty is a schema failure" "$out" "status=FAILED"
  has "a final review of $empty names schema" "$out" "reason=schema"
  check "a final review of $empty leaves no list" "$([ -e "$TMP/out.json" ] && echo list || echo none)" "none"
done

run --kind task
check "a task review without --prompt is a usage error" "$rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
