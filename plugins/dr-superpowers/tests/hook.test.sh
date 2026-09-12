#!/usr/bin/env bash
# The SessionStart hook must inject the using-superpowers entry point in the
# Claude Code JSON shape, persist the session record keyed by sanitized cwd,
# tolerate malformed stdin (inject anyway, persist nothing), and always exit 0.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/session-start.sh"
HOOKS="$HERE/../hooks/hooks.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp '/tmp/fake-transcript.jsonl' --arg cwd 'D:\repo\example' \
    '{hook_event_name:"SessionStart",session_id:"s-123",transcript_path:$tp,cwd:$cwd,source:"startup"}'
}

# --- well-formed stdin ---
HOME_A="$TMP/a"; mkdir -p "$HOME_A"
out=$(payload | HOME="$HOME_A" bash "$SCRIPT" 2>/dev/null)
status=$?
check "well-formed: exits 0" "$status" "0"
check "well-formed: emits valid JSON" \
  "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "well-formed: event name is SessionStart" \
  "$(jq -r '.hookSpecificOutput.hookEventName // "MISSING"' <<<"$out" 2>/dev/null)" "SessionStart"
check "well-formed: names the plugin root" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c 'Plugin root (run every')" "1"
check "well-formed: additionalContext is non-empty" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "well-formed: context names the entry-point skill" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c 'dr-superpowers:using-superpowers')" "1"
check "well-formed: emits no permissionDecision" \
  "$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' <<<"$out" 2>/dev/null)" "ABSENT"

RECORD="$HOME_A/.claude/dr-superpowers/sessions/D--repo-example.json"
check "well-formed: persists the session record" "$([ -f "$RECORD" ] && echo yes || echo no)" "yes"
check "record: transcript_path" \
  "$(jq -r '.transcript_path // "MISSING"' "$RECORD" 2>/dev/null)" "/tmp/fake-transcript.jsonl"
check "record: session_id" "$(jq -r '.session_id // "MISSING"' "$RECORD" 2>/dev/null)" "s-123"
check "record: source" "$(jq -r '.source // "MISSING"' "$RECORD" 2>/dev/null)" "startup"
check "record: cwd" "$(jq -r '.cwd // "MISSING"' "$RECORD" 2>/dev/null)" 'D:\repo\example'

# --- malformed stdin ---
HOME_B="$TMP/b"; mkdir -p "$HOME_B"
out=$(printf 'not json' | HOME="$HOME_B" bash "$SCRIPT" 2>/dev/null)
status=$?
check "malformed: exits 0" "$status" "0"
check "malformed: still injects the entry point" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "malformed: persists nothing" \
  "$([ -d "$HOME_B/.claude" ] && echo yes || echo no)" "no"

# --- empty stdin ---
HOME_C="$TMP/c"; mkdir -p "$HOME_C"
out=$(printf '' | HOME="$HOME_C" bash "$SCRIPT" 2>/dev/null)
status=$?
check "empty: exits 0" "$status" "0"
check "empty: still injects the entry point" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"

# --- compact source: the snapshot follows the entry point ---
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
mkdir -p "$REPO/.superpowers/handoff"
printf '# Handoff\n\n## Next session\n\n**Next:** Resume at Task 4 (Four).\n' > "$REPO/.superpowers/handoff/latest.md"
TR="$TMP/transcript.jsonl"
MSYS_NO_PATHCONV=1 jq -cn '{type:"user",isSidechain:false,origin:{kind:"human"},message:{role:"user",content:"keep the API stable"}}' > "$TR"
compact_payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$REPO" \
    '{hook_event_name:"SessionStart",session_id:"s-9",transcript_path:$tp,cwd:$cwd,source:"compact"}'
}
HOME_D="$TMP/d"; mkdir -p "$HOME_D"
out=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
status=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
check "compact: exits 0" "$status" "0"
check "compact: emits valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "compact: entry point still injected" "$(grep -c 'dr-superpowers:using-superpowers' <<<"$ctx")" "1"
check "compact: snapshot appended" "$(grep -c '^## Compaction snapshot' <<<"$ctx")" "1"
check "compact: carries the handoff next step" "$(grep -c 'Resume at Task 4 (Four)' <<<"$ctx")" "1"
check "compact: carries the owner prompt" "$(grep -c 'keep the API stable' <<<"$ctx")" "1"
check "compact: under the 10,000-character hook cap" "$([ "${#ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
startup_ctx=$(payload | HOME="$HOME_A" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "startup: no snapshot" "$(grep -c '^## Compaction snapshot' <<<"$startup_ctx")" "0"

# A prompt holding pasted terminal output carries raw C0 controls; JSON forbids
# them unescaped inside a string, so the hook must not emit them.
MSYS_NO_PATHCONV=1 jq -cn --arg c "$(printf 'red \033[31malert\033[0m done')" \
  '{type:"user",isSidechain:false,origin:{kind:"human"},message:{role:"user",content:$c}}' > "$TR"
esc_out=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "compact: control bytes keep the output valid JSON" \
  "$(jq -e . >/dev/null 2>&1 <<<"$esc_out" && echo yes || echo no)" "yes"
check "compact: control bytes stripped from the context" \
  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$esc_out" 2>/dev/null | grep -c $'\033')" "0"

# --- hooks.json wiring ---
check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "hooks.json registers SessionStart with the full matcher" \
  "$(jq -r '.hooks.SessionStart[0].matcher // "MISSING"' "$HOOKS" 2>/dev/null)" "startup|resume|clear|compact"
check "hooks.json is synchronous" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].async // false' "$HOOKS" 2>/dev/null)" "false"
check "hooks.json forces the bash interpreter" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].shell // "MISSING"' "$HOOKS" 2>/dev/null)" "bash"
check "hooks.json has no PreToolUse entry" \
  "$(jq -r 'if .hooks.PreToolUse then "present" else "ABSENT" end' "$HOOKS" 2>/dev/null)" "ABSENT"
check "session-start.sh parses" \
  "$(bash -n "$SCRIPT" 2>/dev/null && echo yes || echo no)" "yes"

# The entry point rides in every session's baseline and shares the hook's
# 10,000-character cap with the compaction snapshot.
check "entry point is at most 4,800 bytes" \
  "$([ "$(wc -c < "$HERE/../skills/using-superpowers/SKILL.md")" -le 4800 ] && echo yes || echo no)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
