#!/usr/bin/env bash
# Acceptance tests for the "agy lane: Gemini first" spec
# (docs/dforge/specs/2026-11-03-agy-gemini-first-design.md), statements A1-A14.
# Each test is written from the statement's text and reaches the behaviour
# through the file the plugin ships (reference/ladder.md), scripts/run-agy-task.sh,
# scripts/agy-gate, the session file the two share, and scripts/lib/executor-session.sh.
# The agy CLI is the repository's stub (tests/fixtures/stub-agy); the real agy,
# ~/.claude and ~/.gemini are never reached.
# Usage:
#   bash agy-gemini-first.acceptance.test.sh            run every test
#   bash agy-gemini-first.acceptance.test.sh A5 A9      run the named tests
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
S="$PLUGIN/scripts"
LADDER="$PLUGIN/reference/ladder.md"
STUBDIR="$HERE/fixtures/stub-agy"
ONLY=" $* "

pass=0 fail=0 skipped=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
skip() { printf 'skip - %s\n' "$1"; skipped=$((skipped + 1)); }
selected() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home" DR_AGY_SESSION_DIR="$TMP/sessions" DR_AGY_POLICY="$TMP/policy.json" \
  CLAUDE_CODE_SESSION_ID=agy-gemini-first-acceptance CLAUDE_PROJECT_DIR=
unset CLAUDE_CONFIG_DIR AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
jq '.trust.smoke = "pass"' "$PLUGIN/reference/agy-policy.json" > "$DR_AGY_POLICY"
export STUB_AGY_ARGS_LOG="$TMP/args.log"
export PATH="$STUBDIR:$PATH"
session_file="$DR_AGY_SESSION_DIR/$CLAUDE_CODE_SESSION_ID.json"

# --- helpers ------------------------------------------------------------------
block() { # block <fence tag>: the non-blank lines of a fenced block in the ladder
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER" | tr -d '\r'
}
section() { # section <file> <heading line>: the body up to the next "## " heading
  awk -v h="$2" '$0 == h { f = 1; next } f && /^## / { exit } f { print }' "$1" | tr -d '\r'
}
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
epoch_of() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$1" +%s 2>/dev/null; }
within() { # within <epoch> <want> <slack>
  local d=$(( $1 - $2 )); [ "$d" -lt 0 ] && d=$(( -d ))
  if [ "$d" -le "$3" ] 2>/dev/null; then echo yes; else echo no; fi
}
gfield() { tr ' ' '\n' <<<"$1" | sed -n "s/^$2=//p"; } # gfield <gate line> <key>

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GATE_STUB_LINE:-agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=cache}"\n' > "$TMP/gate-stub"
STUB_GATE="$TMP/gate-stub"
export AGY_TASK_GATE="$STUB_GATE"
real_gate() { unset AGY_TASK_GATE; }
fake_gate() { export AGY_TASK_GATE="$STUB_GATE"; }
gate_line() { bash "$S/agy-gate" "$@" 2>/dev/null | tail -1 | tr -d '\r'; }

SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$STUBDIR/agy" 2>/dev/null | tr -d '\r')

calls() { if [ -f "$STUB_AGY_ARGS_LOG" ]; then grep -c '^-p$' "$STUB_AGY_ARGS_LOG" || true; else echo 0; fi; }

git init -q "$TMP/primary"
git -C "$TMP/primary" config user.email fixture@example.com
git -C "$TMP/primary" config user.name Fixture
git -C "$TMP/primary" config core.autocrlf false
printf 'base\n' > "$TMP/primary/base.txt"
git -C "$TMP/primary" add base.txt
git -C "$TMP/primary" commit -qm 'test: seed fixture'
printf 'Implement only the approved files.\n' > "$TMP/brief.md"
printf '["base.txt","out.txt"]\n' > "$TMP/scope.json"
wt=0
newwork() { wt=$((wt + 1)); W="$TMP/work$wt"; R="$TMP/work$wt.report.md"; git -C "$TMP/primary" worktree add -qb "work$wt" "$W"; }
run() { # run [wrapper flags]: a Claude Sonnet medium run unless the flags say otherwise
  newwork
  timeout 90 bash "$S/run-agy-task.sh" --cwd "$W" --task-id task-one --write-set "$TMP/scope.json" \
    --brief "$TMP/brief.md" --report "$R" --model claude-sonnet-5-5 --effort medium "$@" > "$TMP/out" 2> "$TMP/err"
}
dry_rc() { timeout 30 bash "$S/run-agy-task.sh" --brief "$TMP/brief.md" --report "$TMP/dry.md" --cwd "$TMP/primary" --dry-run "$@" >/dev/null 2>&1; echo $?; }
seed_open() { rm -rf "$DR_AGY_SESSION_DIR"; mkdir -p "$DR_AGY_SESSION_DIR"
  printf '{"session_id":"%s","usable":true,"review":false,"lane":true,"reason":"ok","resets_at":null,"resets_at_epoch":null}\n' \
    "$CLAUDE_CODE_SESSION_ID" > "$session_file"; }
sfield() { jq -r "$1 | tostring" "$session_file" 2>/dev/null | tr -d '\r'; }
now() { date -u +%s; }

RESET_ERR='RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h2m3s.'
BARE_ERR='Quota exceeded for this account'
GEMINI=(--model gemini-3.8-flash --effort medium)
CLAUDE=(--model claude-sonnet-5-5 --effort medium)

mkdir -p "$TMP/stderrshim"
cat > "$TMP/stderrshim/agy" <<SHIM
#!/usr/bin/env bash
case "\${1:-}" in --version|models) exec "$STUBDIR/agy" "\$@" ;; esac
printf 'HTTP 429 Too Many Requests: RESOURCE_EXHAUSTED quota reached. Resets in 1h2m3s.\n' >&2
printf '{"conversation_id":"","status":"ERROR","response":""}\n'
exit 1
SHIM
chmod +x "$TMP/stderrshim/agy"

# --- A1 ----------------------------------------------------------------------
a1() {
  local rows; rows=$(block agy-assignment | awk '{ print $1 "=" $2 " " $3 }' | tr '\n' ';')
  check "A1: agy-assignment names flash medium for 0-2, Argon low for 3-4 and Argon high for 5-8" "$rows" \
    "0=gemini-3.8-flash medium;1=gemini-3.8-flash medium;2=gemini-3.8-flash medium;3=gemini-4-argon low;4=gemini-4-argon low;5=gemini-4-argon high;6=gemini-4-argon high;7=gemini-4-argon high;8=gemini-4-argon high;"
}

# --- A2 (neg) ----------------------------------------------------------------
a2() {
  check "A2: no agy-assignment row names a claude- model" "$(block agy-assignment | awk '{ print $2 }' | grep -c '^claude-')" "0"
  check "A2: no agy-successor row names claude-opus-5-5" "$(block agy-successor | grep -c 'claude-opus-5-5')" "0"
  check "A2: no agy-timeout row names claude-opus-5-5" "$(block agy-timeout | grep -c 'claude-opus-5-5')" "0"
  check "A2: the agy-assignment block is not empty" "$(block agy-assignment | wc -l | tr -d ' ')" "9"
}

# --- A3 ----------------------------------------------------------------------
a3() {
  local b; b=$(block agy-successor)
  check "A3: flash medium falls back to Sonnet medium" "$(grep -cx 'gemini-3.8-flash/medium claude-sonnet-5-5/medium' <<<"$b")" "1"
  check "A3: Argon low falls back to Sonnet medium" "$(grep -cx 'gemini-4-argon/low claude-sonnet-5-5/medium' <<<"$b")" "1"
  check "A3: Argon high falls back to Sonnet high" "$(grep -cx 'gemini-4-argon/high claude-sonnet-5-5/high' <<<"$b")" "1"
  check "A3: Sonnet medium is handed back" "$(grep -cx 'claude-sonnet-5-5/medium HANDBACK' <<<"$b")" "1"
  check "A3: Sonnet high is handed back" "$(grep -cx 'claude-sonnet-5-5/high HANDBACK' <<<"$b")" "1"
}

# --- A4 ----------------------------------------------------------------------
a4() {
  local t; t=$(block agy-timeout)
  check "A4: Argon low times out at 900" "$(grep -cx 'gemini-4-argon/low 900' <<<"$t")" "1"
  check "A4: Argon high times out at 1500" "$(grep -cx 'gemini-4-argon/high 1500' <<<"$t")" "1"
  local reach have
  reach=$({ block agy-assignment | awk '{ print $2 "/" $3 }'
            block agy-successor | awk '{ print $1; print $2 }' | grep -vx HANDBACK; } | sort -u | tr '\n' ' ')
  have=$(awk '{ print $1 }' <<<"$t" | sort -u | tr '\n' ' ')
  check "A4: the timeout rows are exactly the reachable rungs" "$have" "$reach"
  check "A4: the reachable rungs are the five the spec names" "$reach" \
    "claude-sonnet-5-5/high claude-sonnet-5-5/medium gemini-3.8-flash/medium gemini-4-argon/high gemini-4-argon/low "
}

# --- A5 ----------------------------------------------------------------------
a5() {
  fake_gate; unset GATE_STUB_LINE
  rm -f "$STUB_AGY_ARGS_LOG"
  run --model claude-sonnet-5-5 --effort medium
  check "A5: the wrapper runs claude-sonnet-5-5 medium" "$?" "0"
  check "A5: that run launched agy" "$(calls)" "1"
  run --model claude-sonnet-5-5 --effort high
  check "A5: the wrapper runs claude-sonnet-5-5 high" "$?" "0"
  check "A5: that run launched agy" "$(calls)" "2"
  run --model claude-opus-5-5 --effort high
  check "A5: claude-opus-5-5, in neither block, is refused with exit 2" "$?" "2"
  run --model gpt-4o --effort medium
  check "A5: an unknown model is refused with exit 2" "$?" "2"
  check "A5: the refused models never launched agy" "$(calls)" "2"
  check "A5: a dry run refuses claude-opus-5-5 with exit 2" "$(dry_rc --model claude-opus-5-5 --effort high)" "2"
  check "A5: a dry run admits claude-sonnet-5-5 high" "$(dry_rc --model claude-sonnet-5-5 --effort high)" "0"
}

# --- A6 ----------------------------------------------------------------------
a6() {
  if [ "$SPAWNABLE" != yes ]; then skip "A6: the real gate needs a probe that can run the stub"; return; fi
  real_gate; seed_open
  STUB_AGY_MODE=error STUB_AGY_ERROR="$RESET_ERR" run "${GEMINI[@]}"
  local after; after=$(now)
  local line; line=$(gate_line)
  check "A6: after a Gemini quota the gate line reads lane=false" "$(gfield "$line" lane)" "false"
  check "A6: after a Gemini quota the gate line reads reason=quota" "$(gfield "$line" reason)" "quota"
  local at; at=$(gfield "$line" resets_at)
  check "A6: resets_at is an ISO 8601 UTC time" "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<<"$at")" "1"
  check "A6: resets_at is 3723 s after the wrapper exits, give or take 5 s" \
    "$(within "$(epoch_of "$at")" "$((after + 3723))" 5)" "yes"
  jq '.resets_at_epoch = 1000' "$session_file" > "$session_file.tmp" && mv -f "$session_file.tmp" "$session_file"
  line=$(gate_line)
  check "A6: once the reset has passed the next gate call probes" "$(gfield "$line" source)" "probe"
  check "A6: once the reset has passed the lane is open" "$(gfield "$line" lane)" "true"
}

# --- A7 ----------------------------------------------------------------------
a7() {
  if [ "$SPAWNABLE" != yes ]; then skip "A7: the real gate needs a probe that can run the stub"; return; fi
  real_gate; seed_open
  STUB_AGY_MODE=error STUB_AGY_ERROR="$RESET_ERR" run "${CLAUDE[@]}"
  local after; after=$(now)
  local line; line=$(gate_line)
  check "A7: after a Claude quota the lane is still open" "$(gfield "$line" lane)" "true"
  check "A7: after a Claude quota the fallback is off" "$(gfield "$line" fallback)" "off"
  local at; at=$(gfield "$line" fallback_resets_at)
  check "A7: fallback_resets_at is 3723 s after the wrapper exits, give or take 5 s" \
    "$(within "$(epoch_of "$at")" "$((after + 3723))" 5)" "yes"
  local n rc; n=$(calls)
  run "${GEMINI[@]}"; rc=$?
  check "A7: a Gemini run still launches agy" "$(calls)" "$((n + 1))"
  check "A7: a Gemini run still finishes" "$rc" "0"
}

# --- A8 (neg) ----------------------------------------------------------------
a8() {
  fake_gate
  local n lines i
  lines=(
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=2099-01-01T00:00:00Z source=cache"
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=- source=cache"
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache"
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=maybe fallback_resets_at=- source=cache"
  )
  local names=("fallback=off with a reset time" "fallback=off with no reset time" "a line without the fallback field" "a fallback value that is not on")
  rm -f "$STUB_AGY_ARGS_LOG"
  for i in 0 1 2 3; do
    n=$(calls)
    GATE_STUB_LINE="${lines[$i]}" run "${CLAUDE[@]}"
    check "A8: a claude- model is refused with exit 2 under ${names[$i]}" "$?" "2"
    check "A8: agy is never launched under ${names[$i]}" "$(calls)" "$n"
  done
  n=$(calls)
  GATE_STUB_LINE="agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=cache" run "${CLAUDE[@]}"
  check "A8: a claude- model runs when the line says fallback=on" "$?" "0"
  check "A8: and then launches agy" "$(calls)" "$((n + 1))"
  n=$(calls)
  GATE_STUB_LINE="${lines[0]}" run "${GEMINI[@]}"
  check "A8: a Gemini model still runs while the fallback is off" "$?" "0"
  check "A8: and launches agy" "$(calls)" "$((n + 1))"
}

# --- A9 (neg) ----------------------------------------------------------------
seed_fallback() { # an open session carrying an unexpired fallback mark
  rm -rf "$DR_AGY_SESSION_DIR"; mkdir -p "$DR_AGY_SESSION_DIR"
  printf '{"session_id":"%s","usable":true,"review":false,"lane":true,"reason":"ok","resets_at":null,"resets_at_epoch":null,"fallback":{"usable":false,"reason":"quota","resets_at":"2099-01-01T00:00:00Z","resets_at_epoch":4070908800}}\n' \
    "$CLAUDE_CODE_SESSION_ID" > "$session_file"
}
fb_state() { sfield '.fallback | [.usable, .reason, .resets_at, .resets_at_epoch] | map(tostring) | join("/")'; }
a9() {
  local want="false/quota/2099-01-01T00:00:00Z/4070908800"
  if [ "$SPAWNABLE" = yes ]; then
    real_gate; seed_fallback
    local line; line=$(gate_line)
    check "A9: a gate call keeps the fallback mark in the file" "$(fb_state)" "$want"
    check "A9: a gate call still reports fallback=off" "$(gfield "$line" fallback)" "off"
    line=$(gate_line --refresh)
    check "A9: a probing gate call answers from a probe" "$(gfield "$line" source)" "probe"
    check "A9: a probe write keeps the fallback mark in the file" "$(fb_state)" "$want"
    check "A9: a probe write still reports fallback=off" "$(gfield "$line" fallback)" "off"
    seed_fallback
    STUB_AGY_MODE=error STUB_AGY_ERROR="$RESET_ERR" run "${GEMINI[@]}"
    check "A9: a Gemini quota closes the lane" "$(sfield '[.usable, .lane] | map(tostring) | join("/")')" "false/false"
    check "A9: a Gemini quota's lane mark keeps the fallback mark" "$(fb_state)" "$want"
    check "A9: the gate still reports fallback=off after the lane mark" "$(gfield "$(gate_line)" fallback)" "off"
  else
    skip "A9: the gate-driven checks need a probe that can run the stub"
  fi
  seed_fallback
  ( . "$S/lib/executor-session.sh"; executor_session_mark_off agy quota 4070000000 )
  check "A9: executor_session_mark_off with a reset keeps the fallback mark" "$(fb_state)" "$want"
  check "A9: executor_session_mark_off does close the lane" "$(sfield '[.usable, .lane] | map(tostring) | join("/")')" "false/false"
  seed_fallback
  ( . "$S/lib/executor-session.sh"; executor_session_mark_off agy quota )
  check "A9: executor_session_mark_off with no reset keeps the fallback mark" "$(fb_state)" "$want"
}

# --- A10 ---------------------------------------------------------------------
a10() {
  if [ "$SPAWNABLE" != yes ]; then skip "A10: the real gate needs a probe that can run the stub"; return; fi
  real_gate; seed_open
  STUB_AGY_MODE=error STUB_AGY_ERROR="$BARE_ERR" run "${GEMINI[@]}"
  local line; line=$(gate_line)
  check "A10: a Gemini quota with no reset closes the lane" "$(gfield "$line" lane)/$(gfield "$line" reason)" "false/quota"
  check "A10: and names no reset time" "$(gfield "$line" resets_at)" "-"
  line=$(gate_line --refresh)
  check "A10: --refresh keeps the lane closed" "$(gfield "$line" lane)/$(gfield "$line" reason)/$(gfield "$line" resets_at)" "false/quota/-"
  check "A10: later calls keep it closed" "$(gfield "$(gate_line)" lane)" "false"

  seed_open
  STUB_AGY_MODE=error STUB_AGY_ERROR="$BARE_ERR" run "${CLAUDE[@]}"
  line=$(gate_line)
  check "A10: a Claude quota with no reset turns the fallback off and leaves the lane" \
    "$(gfield "$line" lane)/$(gfield "$line" fallback)/$(gfield "$line" fallback_resets_at)" "true/off/-"
  line=$(gate_line --refresh)
  check "A10: --refresh keeps the fallback off" \
    "$(gfield "$line" lane)/$(gfield "$line" fallback)/$(gfield "$line" fallback_resets_at)" "true/off/-"
  check "A10: later calls keep it off" "$(gfield "$(gate_line)" fallback)" "off"
}

# --- A11 (neg) ---------------------------------------------------------------
a11() {
  real_gate
  local m
  for m in gemini claude; do
    seed_open
    local args=("${CLAUDE[@]}"); [ "$m" = gemini ] && args=("${GEMINI[@]}")
    PATH="$TMP/stderrshim:$PATH" run "${args[@]}"
    check "A11: the $m run fails" "$?" "1"
    check "A11: the stderr-only quota is labelled quota in the report" "$(grep -c '^reason=quota$' "$R")" "1"
    check "A11: a stderr-only quota on a $m run leaves the lane unmarked" "$(sfield '[.usable, .lane, .reason] | map(tostring) | join("/")')" "true/true/ok"
    check "A11: a stderr-only quota on a $m run writes no fallback mark" "$(sfield 'has("fallback")')" "false"
    if [ "$SPAWNABLE" = yes ]; then
      local line; line=$(gate_line)
      check "A11: the gate after a stderr-only quota on a $m run has the lane open and the fallback on" \
        "$(gfield "$line" lane)/$(gfield "$line" fallback)" "true/on"
    fi
  done
  if [ "$SPAWNABLE" != yes ]; then
    skip "A11: with no session file the real gate must probe, and the probe cannot run the stub"
    return
  fi
  rm -rf "$DR_AGY_SESSION_DIR"
  PATH="$TMP/stderrshim:$PATH" run "${GEMINI[@]}"
  check "A11: with no prior session file a stderr-only quota marks neither lane nor fallback" \
    "$(sfield '[.usable, .lane, (.fallback // "none" | tostring)] | map(tostring) | join("/")')" "true/true/none"
}

# --- A14 ---------------------------------------------------------------------
agy_error_section() { section "$R" '## Agy error'; }
a14() {
  real_gate
  local before after sec until_at
  seed_open; before=$(now)
  STUB_AGY_MODE=error STUB_AGY_ERROR="$RESET_ERR" run "${GEMINI[@]}"; after=$(now)
  sec=$(agy_error_section)
  check "A14: a Gemini quota with a reset reports marked=lane" "$(grep -cx 'marked=lane' <<<"$sec")" "1"
  until_at=$(sed -n 's/^until=//p' <<<"$sec")
  check "A14: and an until= line in ISO 8601 UTC" "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<<"$until_at")" "1"
  check "A14: that until= is the reset, 3723 s after the run" "$(within "$(epoch_of "$until_at")" "$((after + 3723))" 5)" "yes"
  check "A14: marked= sits under reason=quota" "$(grep -A1 -x 'reason=quota' <<<"$sec" | tail -1)" "marked=lane"

  seed_open
  STUB_AGY_MODE=error STUB_AGY_ERROR="$RESET_ERR" run "${CLAUDE[@]}"; after=$(now)
  sec=$(agy_error_section)
  check "A14: a Claude quota with a reset reports marked=fallback" "$(grep -cx 'marked=fallback' <<<"$sec")" "1"
  until_at=$(sed -n 's/^until=//p' <<<"$sec")
  check "A14: and an until= line 3723 s after the run" "$(within "$(epoch_of "$until_at")" "$((after + 3723))" 5)" "yes"

  seed_open
  STUB_AGY_MODE=error STUB_AGY_ERROR="$BARE_ERR" run "${GEMINI[@]}"
  sec=$(agy_error_section)
  check "A14: a Gemini quota with no reset reports marked=lane" "$(grep -cx 'marked=lane' <<<"$sec")" "1"
  check "A14: and no until= line" "$(grep -c '^until=' <<<"$sec")" "0"
  seed_open
  STUB_AGY_MODE=error STUB_AGY_ERROR="$BARE_ERR" run "${CLAUDE[@]}"
  sec=$(agy_error_section)
  check "A14: a Claude quota with no reset reports marked=fallback" "$(grep -cx 'marked=fallback' <<<"$sec")" "1"
  check "A14: and no until= line" "$(grep -c '^until=' <<<"$sec")" "0"

  seed_open
  PATH="$TMP/stderrshim:$PATH" run "${GEMINI[@]}"
  sec=$(agy_error_section)
  check "A14: a stderr-only quota reports marked=none" "$(grep -cx 'marked=none' <<<"$sec")" "1"
  check "A14: and carries no marked=lane or marked=fallback" "$(grep -cE '^marked=(lane|fallback)$' <<<"$sec")" "0"
}

for t in 1 2 3 4 5 6 7 8 9 10 11 14; do
  selected "A$t" && "a$t"
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
