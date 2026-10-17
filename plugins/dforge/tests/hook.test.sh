#!/usr/bin/env bash
# The SessionStart hook must inject the using-forge entry point in the
# Claude Code JSON shape, persist the session record keyed by sanitized cwd and
# by session id, tolerate malformed stdin (inject anyway, persist nothing), and
# always exit 0.
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
check "using-forge states the working-directory contract" \
  "$(grep -cF "with the working directory inside the project's worktree" "$HERE/../skills/using-forge/SKILL.md")" "1"
check "well-formed: additionalContext is non-empty" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "well-formed: context names the entry-point skill" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c 'dforge:using-forge')" "1"
check "well-formed: emits no permissionDecision" \
  "$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' <<<"$out" 2>/dev/null)" "ABSENT"

RECORD="$HOME_A/.claude/dforge/sessions/D--repo-example.json"
check "well-formed: persists the session record" "$([ -f "$RECORD" ] && echo yes || echo no)" "yes"
check "record: transcript_path" \
  "$(jq -r '.transcript_path // "MISSING"' "$RECORD" 2>/dev/null)" "/tmp/fake-transcript.jsonl"
check "record: session_id" "$(jq -r '.session_id // "MISSING"' "$RECORD" 2>/dev/null)" "s-123"
check "record: source" "$(jq -r '.source // "MISSING"' "$RECORD" 2>/dev/null)" "startup"
check "record: cwd" "$(jq -r '.cwd // "MISSING"' "$RECORD" 2>/dev/null)" 'D:\repo\example'

# --- a second session in the same cwd ---
# The cwd record is last writer wins; each session keeps a record of its own.
MSYS_NO_PATHCONV=1 jq -n --arg tp '/tmp/second-transcript.jsonl' --arg cwd 'D:\repo\example' \
  '{hook_event_name:"SessionStart",session_id:"s-456",transcript_path:$tp,cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_A" bash "$SCRIPT" >/dev/null 2>&1
BYID="$HOME_A/.claude/dforge/sessions/by-id"
check "shared cwd: the cwd record names the later session" "$(jq -r '.session_id' "$RECORD" 2>/dev/null)" "s-456"
check "shared cwd: the first session keeps its own record" \
  "$(jq -r '.transcript_path' "$BYID/s-123.json" 2>/dev/null)" "/tmp/fake-transcript.jsonl"
check "shared cwd: the second session has its own record" \
  "$(jq -r '.transcript_path' "$BYID/s-456.json" 2>/dev/null)" "/tmp/second-transcript.jsonl"

# --- records a month old are pruned; the session's own and recent ones stay ---
printf '{}\n' > "$BYID/s-old.json"
printf '{}\n' > "$HOME_A/.claude/dforge/sessions/D--gone-worktree.json"
touch -d '40 days ago' "$BYID/s-old.json" "$HOME_A/.claude/dforge/sessions/D--gone-worktree.json" "$BYID/s-123.json"
payload | HOME="$HOME_A" bash "$SCRIPT" >/dev/null 2>&1
check "prune: an old session record is removed" "$([ -e "$BYID/s-old.json" ] && echo yes || echo no)" "no"
check "prune: an old checkout record is removed" "$([ -e "$HOME_A/.claude/dforge/sessions/D--gone-worktree.json" ] && echo yes || echo no)" "no"
check "prune: the starting session's record is rewritten, not removed" "$(jq -r '.session_id' "$BYID/s-123.json" 2>/dev/null)" "s-123"
check "prune: a recent record stays" "$([ -e "$BYID/s-456.json" ] && echo yes || echo no)" "yes"

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
mkdir -p "$REPO/.forge/handoff"
printf '# Handoff\n\n## Next session\n\n**Next:** Resume at Task 4 (Four).\n' > "$REPO/.forge/handoff/latest.md"
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
check "compact: entry point still injected" "$(grep -c 'dforge:using-forge' <<<"$ctx")" "1"
check "compact: snapshot appended" "$(grep -c '^## Compaction snapshot' <<<"$ctx")" "1"
check "compact: carries the handoff next step" "$(grep -c 'Resume at Task 4 (Four)' <<<"$ctx")" "1"
check "compact: carries the owner prompt" "$(grep -c 'keep the API stable' <<<"$ctx")" "1"
check "compact: under the 10,000-character hook cap" "$([ "${#ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
check "an existing state directory ignores itself" "$(git -C "$REPO" status --porcelain --untracked-files=all -- .forge)" ""
BARE="$TMP/bare-repo"
git init -q -b main "$BARE"
MSYS_NO_PATHCONV=1 jq -n --arg cwd "$BARE" '{hook_event_name:"SessionStart",session_id:"s-10",transcript_path:"",cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_D" bash "$SCRIPT" >/dev/null 2>&1
check "a checkout without a state directory gains none" "$([ -e "$BARE/.forge" ] && echo yes || echo no)" "no"
LINKED="$TMP/linked-repo"
git init -q -b main "$LINKED"
mkdir -p "$LINKED/.forge" "$TMP/outside"
ln -s "$TMP/outside/planted" "$LINKED/.forge/.gitignore"
MSYS_NO_PATHCONV=1 jq -n --arg cwd "$LINKED" '{hook_event_name:"SessionStart",session_id:"s-11",transcript_path:"",cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_D" bash "$SCRIPT" >/dev/null 2>&1
check "the state ignore is never written through a link" "$([ -e "$TMP/outside/planted" ] && echo yes || echo no)" "no"
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

# --- a roadmap project: its position rides in every session ---
mkdir -p "$REPO/docs/forge/registers" "$REPO/docs/forge/specs"
: > "$REPO/docs/forge/specs/shop-design.md"
printf '# M1 — item register\n\n**Source:** roadmap\n**Covers:** docs/superpowers/specs/shop-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Billing | - | - | done | - |\n| 2 | Search | - | - | open | - |\n' \
  > "$REPO/docs/forge/registers/m1.md"
printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/superpowers/specs/shop-design.md\n\n| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n| M1 | MVP | every epic resolved | docs/superpowers/registers/m1.md | open | - |\n' \
  > "$REPO/docs/forge/roadmap.md"
startup_payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$REPO" \
    '{hook_event_name:"SessionStart",session_id:"s-10",transcript_path:$tp,cwd:$cwd,source:"startup"}'
}
rm_out=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "roadmap: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$rm_out" && echo yes || echo no)" "yes"
check "roadmap: the position is injected" \
  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$rm_out" | grep -c '^Roadmap: M1 MVP, 1 of 2 epics resolved, open: #2 Search\.')" "1"
rm_ctx=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "roadmap: survives compaction alongside the snapshot" "$(grep -c '^Roadmap: M1 MVP' <<<"$rm_ctx")" "1"
check "roadmap: still under the 10,000-character hook cap" "$([ "${#rm_ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
check "no roadmap: nothing injected" "$(grep -c '^Roadmap:' <<<"$startup_ctx")" "0"

# --- a pre-3.0 directory left behind is named, with the command that moves it ---
check "3.0 layout: no migration line" "$(grep -c 'pre-3.0 layout' <<<"$rm_ctx")" "0"
mkdir -p "$REPO/.superpowers"
lg_out=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "pre-3.0: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$lg_out" && echo yes || echo no)" "yes"
check "pre-3.0: the migration line is injected" \
  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$lg_out" | grep -cF "dforge: this repository still uses the pre-3.0 layout ($(git -C "$REPO" rev-parse --show-toplevel)/.superpowers); run bash $(cd "$HERE/.." && pwd)/scripts/forge-migrate")" "1"
rm -rf "$REPO/.superpowers"

# --- workflow settings ride in every session as one line ---
if command -v node >/dev/null 2>&1; then
  HOME_S="$TMP/s"; mkdir -p "$HOME_S/.dforge"
  s_ctx=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  check "settings: nothing injected at the defaults" "$(grep -c '^dforge settings in force' <<<"$s_ctx")" "0"
  printf '{"worktree":"always","designApproval":"whole","codexLane":false}\n' > "$HOME_S/.dforge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null)
  check "settings: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$s_out" && echo yes || echo no)" "yes"
  check "settings: the changed skill keys are injected" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c '^dforge settings in force (each replaces the matching question or default in the skills): worktree=always; designApproval=whole$')" "1"
  s_ctx=$(compact_payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  check "settings: the line survives compaction" "$(grep -c '^dforge settings in force' <<<"$s_ctx")" "1"
  check "settings: still under the 10,000-character hook cap" "$([ "${#s_ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
  printf 'not json' > "$HOME_S/.dforge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null); status=$?
  check "settings: a broken file still exits 0" "$status" "0"
  check "settings: a broken file injects no line" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c '^dforge settings in force')" "0"
  check "settings: a broken file keeps the entry point" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c 'dforge:using-forge')" "1"
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
check "session-start.sh parses" \
  "$(bash -n "$SCRIPT" 2>/dev/null && echo yes || echo no)" "yes"

# The entry point rides in every session's baseline and shares the hook's
# 10,000-character cap with the compaction snapshot.
check "entry point is at most 5,100 bytes" \
  "$([ "$(wc -c < "$HERE/../skills/using-forge/SKILL.md")" -le 5100 ] && echo yes || echo no)" "yes"

# The project-state skills and test-simplifier must be reachable from the entry point, which
# is the only skill list a cold session sees.
ENTRY="$HERE/../skills/using-forge/SKILL.md"
for s in project-status running-gates distilling-docs test-simplifier planning-a-product closing-a-milestone; do
  if grep -qF -- "dforge:$s" "$ENTRY"; then
    printf 'ok   - routing names dforge:%s\n' "$s"; pass=$((pass + 1))
  else
    printf 'FAIL - routing names dforge:%s\n' "$s"; fail=$((fail + 1))
  fi
done
if grep -qF -- 'Before the final review or merge' "$ENTRY"; then
  printf 'ok   - gates row is worded by workflow position\n'; pass=$((pass + 1))
else
  printf 'FAIL - gates row is worded by workflow position\n'; fail=$((fail + 1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
