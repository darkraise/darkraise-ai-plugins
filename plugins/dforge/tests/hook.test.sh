#!/usr/bin/env bash
# The SessionStart hook must inject the using-dforge entry point in the
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
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c '^Plugin root: ')" "1"
check "well-formed: the plugin root line states the working-directory contract" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c ' — call scripts by this path, with the working directory inside the project$')" "1"
check "well-formed: additionalContext is non-empty" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "well-formed: context names the entry-point skill" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c 'dforge:using-dforge')" "1"
check "well-formed: the entry routes to the three skills and no other" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -oE 'dforge:[a-z0-9-]+' | sort -u | tr '\n' ' ')" \
  "dforge:migrate dforge:systematic-debugging dforge:ui-ux dforge:using-dforge "
check "well-formed: emits no permissionDecision" \
  "$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' <<<"$out" 2>/dev/null)" "ABSENT"

RECORD="$HOME_A/.claude/dforge/sessions/D--repo-example.json"
check "well-formed: persists the session record" "$([ -f "$RECORD" ] && echo yes || echo no)" "yes"
check "record: transcript_path" \
  "$(jq -r '.transcript_path // "MISSING"' "$RECORD" 2>/dev/null)" "/tmp/fake-transcript.jsonl"
check "record: session_id" "$(jq -r '.session_id // "MISSING"' "$RECORD" 2>/dev/null)" "s-123"
check "record: source" "$(jq -r '.source // "MISSING"' "$RECORD" 2>/dev/null)" "startup"
check "record: cwd" "$(jq -r '.cwd // "MISSING"' "$RECORD" 2>/dev/null)" 'D:\repo\example'

# --- a second session in the same cwd: the record names the later one ---
MSYS_NO_PATHCONV=1 jq -n --arg tp '/tmp/second-transcript.jsonl' --arg cwd 'D:\repo\example' \
  '{hook_event_name:"SessionStart",session_id:"s-456",transcript_path:$tp,cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_A" bash "$SCRIPT" >/dev/null 2>&1
SESSIONS="$HOME_A/.claude/dforge/sessions"
check "shared cwd: the cwd record names the later session" "$(jq -r '.session_id' "$RECORD" 2>/dev/null)" "s-456"
check "the checkout record is the only thing a start writes" "$(cd "$SESSIONS" && find . -mindepth 1 | sort | tr '\n' ' ')" "./D--repo-example.json "

# --- records a month old are pruned, with the per-session files of earlier versions ---
mkdir -p "$SESSIONS/by-id" "$SESSIONS/cockpit"
printf '{}\n' > "$SESSIONS/by-id/s-old.json"
printf '{}\n' > "$SESSIONS/by-id/s-recent.json"
printf 'x\n' > "$SESSIONS/cockpit/s-old"
printf '{}\n' > "$SESSIONS/D--gone-worktree.json"
touch -d '40 days ago' "$SESSIONS/by-id/s-old.json" "$SESSIONS/cockpit/s-old" "$SESSIONS/D--gone-worktree.json" "$RECORD"
payload | HOME="$HOME_A" bash "$SCRIPT" >/dev/null 2>&1
check "prune: an old checkout record is removed" "$([ -e "$SESSIONS/D--gone-worktree.json" ] && echo yes || echo no)" "no"
check "prune: an earlier version's old session record is removed" "$([ -e "$SESSIONS/by-id/s-old.json" ] && echo yes || echo no)" "no"
check "prune: an earlier version's old heartbeat is removed" "$([ -e "$SESSIONS/cockpit/s-old" ] && echo yes || echo no)" "no"
check "prune: the starting checkout's record is rewritten, not removed" "$(jq -r '.session_id' "$RECORD" 2>/dev/null)" "s-123"
check "prune: a recent file stays" "$([ -e "$SESSIONS/by-id/s-recent.json" ] && echo yes || echo no)" "yes"

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

# --- compact source: the entry point alone, with no snapshot ---
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
mkdir -p "$REPO/.dforge/handoff"
printf '# Handoff\n\n## Next session\n\n**Next:** Resume at Task 4 (Four).\n' > "$REPO/.dforge/handoff/latest.md"
mkdir -p "$REPO/.dforge/sdd/p1"
printf 'Task 1: complete\n' > "$REPO/.dforge/sdd/p1/progress.md"
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
check "compact: entry point still injected" "$(grep -c 'dforge:using-dforge' <<<"$ctx")" "1"
check "compact: no snapshot" "$(grep -c '^## Compaction snapshot' <<<"$ctx")" "0"
check "compact: an earlier version's handoff note is not read" "$(grep -c 'Resume at Task 4 (Four)' <<<"$ctx")" "0"
check "compact: the transcript is not read" "$(grep -c 'keep the API stable' <<<"$ctx")" "0"
check "compact: the context is the startup context" "$ctx" "$(MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$REPO" '{hook_event_name:"SessionStart",session_id:"s-9",transcript_path:$tp,cwd:$cwd,source:"startup"}' | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')"
check "compact: under the 10,000-character hook cap" "$([ "${#ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
check "an existing state directory ignores itself" "$(git -C "$REPO" status --porcelain --untracked-files=all -- .dforge)" ""
BARE="$TMP/bare-repo"
git init -q -b main "$BARE"
MSYS_NO_PATHCONV=1 jq -n --arg cwd "$BARE" '{hook_event_name:"SessionStart",session_id:"s-10",transcript_path:"",cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_D" bash "$SCRIPT" >/dev/null 2>&1
check "a checkout without a state directory gains none" "$([ -e "$BARE/.dforge" ] && echo yes || echo no)" "no"
LINKED="$TMP/linked-repo"
git init -q -b main "$LINKED"
mkdir -p "$LINKED/.dforge" "$TMP/outside"
ln -s "$TMP/outside/planted" "$LINKED/.dforge/.gitignore"
MSYS_NO_PATHCONV=1 jq -n --arg cwd "$LINKED" '{hook_event_name:"SessionStart",session_id:"s-11",transcript_path:"",cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_D" bash "$SCRIPT" >/dev/null 2>&1
check "the state ignore is never written through a link" "$([ -e "$TMP/outside/planted" ] && echo yes || echo no)" "no"
# --- an earlier version's roadmap injects nothing ---
mkdir -p "$REPO/docs/dforge/registers" "$REPO/docs/dforge/specs"
: > "$REPO/docs/dforge/specs/shop-design.md"
printf '# M1 — item register\n\n**Source:** roadmap\n**Covers:** docs/superpowers/specs/shop-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Billing | - | - | done | - |\n| 2 | Search | - | - | open | - |\n' \
  > "$REPO/docs/dforge/registers/m1.md"
printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/superpowers/specs/shop-design.md\n\n| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n| M1 | MVP | every epic resolved | docs/superpowers/registers/m1.md | open | - |\n' \
  > "$REPO/docs/dforge/roadmap.md"
startup_payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$REPO" \
    '{hook_event_name:"SessionStart",session_id:"s-10",transcript_path:$tp,cwd:$cwd,source:"startup"}'
}
rm_out=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "roadmap: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$rm_out" && echo yes || echo no)" "yes"
rm_ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$rm_out")
check "roadmap: no position line" "$(grep -c '^Roadmap:' <<<"$rm_ctx")" "0"

# --- an older directory left behind is named, with the skill that moves it ---
check "4.0 layout: no migration line" "$(grep -c 'still uses an older layout' <<<"$rm_ctx")" "0"
mkdir -p "$REPO/.superpowers"
lg_out=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "older layout: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$lg_out" && echo yes || echo no)" "yes"
check "older layout: the migration line is injected" \
  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$lg_out" | grep -cF "dforge: this repository still uses an older layout ($(git -C "$REPO" rev-parse --show-toplevel)/.superpowers); run the dforge:migrate skill (/dforge:migrate)")" "1"
rm -rf "$REPO/.superpowers"

# --- an earlier version's workflow settings inject nothing ---
if command -v node >/dev/null 2>&1; then
  HOME_S="$TMP/s"; mkdir -p "$HOME_S/.dforge"
  printf '{"worktree":"always","designApproval":"whole","codexLane":false}\n' > "$HOME_S/.dforge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>"$TMP/s-err"); status=$?
  check "settings: removed keys still exit 0" "$status" "0"
  check "settings: removed keys inject no line" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c 'dforge settings in force')" "0"
  check "settings: removed keys print nothing on stderr" "$(cat "$TMP/s-err")" ""
  printf 'not json' > "$HOME_S/.dforge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null); status=$?
  check "settings: a broken file still exits 0" "$status" "0"
  check "settings: a broken file keeps the entry point" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c 'dforge:using-dforge')" "1"
fi

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
check "hooks.json has no SubagentStop entry" \
  "$(jq -r 'if .hooks.SubagentStop then "present" else "ABSENT" end' "$HOOKS" 2>/dev/null)" "ABSENT"
check "hooks.json names only scripts that exist" \
  "$(jq -r '.hooks[][].hooks[].command' "$HOOKS" | sed -E 's|.*/scripts/([^"]+)".*|\1|' | while IFS= read -r name; do [ -f "$HERE/../scripts/$name" ] || printf '%s ' "$name"; done)" ""
check "session-start.sh parses" \
  "$(bash -n "$SCRIPT" 2>/dev/null && echo yes || echo no)" "yes"

# The entry point rides in every session's baseline and shares the hook's
# 10,000-character cap with the older-layout line and darkmem's lines.
check "entry point is at most 5,500 bytes" \
  "$([ "$(wc -c < "$HERE/../skills/using-dforge/SKILL.md")" -le 5500 ] && echo yes || echo no)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
